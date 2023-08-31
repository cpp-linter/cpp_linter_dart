import 'dart:convert';
import 'dart:io';
import 'package:cpp_linter_dart/clang_format.dart';
import 'package:cpp_linter_dart/clang_tidy.dart';
import 'package:http/http.dart' as requests;
import 'common.dart';
import 'logger.dart';
import 'git.dart';

/// Corresponds `GITHUB_API_URL` environment variable.
const githubApiUrl = String.fromEnvironment(
  'GITHUB_API_URL',
  defaultValue: 'https://api.github.com',
);

/// A [List] of the protocol and domain corresponding to [githubApiUrl].
final ghApiUri = githubApiUrl.split('://');

/// A path used in CI to output a step summary
final githubStepSummary = String.fromEnvironment('GITHUB_STEP_SUMMARY');

/// Corresponds `GITHUB_REPOSITORY` environment variable.
const githubRepository = String.fromEnvironment('GITHUB_REPOSITORY');

/// Corresponds `GITHUB_SHA` environment variable.
const githubSha = String.fromEnvironment('GITHUB_SHA');

/// Corresponds `GITHUB_EVENT_NAME` environment variable.
const githubEventName = String.fromEnvironment(
  'GITHUB_EVENT_NAME',
  defaultValue: 'unknown',
);

/// Corresponds `GITHUB_WORKSPACE` environment variable.
const githubWorkspace = String.fromEnvironment('GITHUB_WORKSPACE');

/// Corresponds `GITHUB_EVENT_PAYLOAD` environment variable.
const githubEventPath = String.fromEnvironment('GITHUB_EVENT_PAYLOAD');

/// A [Map] parsed from the file pointed to by [githubEventPath].
final Map<String, Object> ghEventPayload = githubEventPath.isEmpty
    ? {}
    : jsonDecode(
        File(githubEventPath).readAsStringSync(),
      );

/// Corresponds `GITHUB_TOKEN` environment variable (or `GIT_REST_API` if
/// `GITHUB_TOKEN` is not set).
const githubToken = String.fromEnvironment(
  'GITHUB_TOKEN',
  defaultValue: String.fromEnvironment('GIT_REST_API'),
);

/// Creates a [Map] for use as a header to Github REST API calls.
/// Set the [useDiff] parameter to `true` to enable diff formatted payloads
/// returned. By default, the payload is formatted as `text/json`.
///
/// If [githubToken] is set, then it is used as `Authorization` token.
Map<String, String> makeHeaders({bool useDiff = false}) {
  var fmt = useDiff ? 'diff' : 'text/json';
  var headers = {'Accept': 'application/vnd.github.$fmt'};
  if (githubToken.isNotEmpty) {
    headers['Authorization'] = 'token $githubToken';
  }
  return headers;
}

/// Use the Github REST API to get a list of changed files according to the
/// [githubEventName].
Future<List<FileObj>> getListOfChangedFiles() async {
  if (isOnRunner) {
    var urlPath = 'repos/$githubRepository';
    if (githubEventName == 'pull_request') {
      urlPath = '$urlPath/pulls/${ghEventPayload['number']}';
    } else {
      if (githubEventName != 'push') {
        log.warning(
          'Triggered on unsupported event $githubEventName; '
          'behaving like a commit',
        );
      }
      urlPath = '$urlPath/commits/$githubSha';
    }
    var url = Uri(
      scheme: ghApiUri.first,
      host: ghApiUri.last,
      path: urlPath,
    );
    log.info('Fetching files list from url: $url');
    var response = await requests.get(url, headers: makeHeaders(useDiff: true));
    logRequestResponse(response);
    return parseDiff(response.body);
  }
  return parseDiff(await getDiff());
}

int makeAnnotations(
  List<FormatFix> formatAdvice,
  List<TidyNotification> tidyNotes,
  bool fileAnnotations,
  String style,
  bool linesChangedOnly,
) {
  var total = 0;
  for (final advice in formatAdvice) {
    final message = advice.logCommand(style, linesChangedOnly);
    total += message.isNotEmpty ? 1 : 0;
    if (fileAnnotations) {
      logCommander.info(message);
    }
  }
  for (final note in tidyNotes) {
    final message = note.logCommand(linesChangedOnly);
    total += message.isNotEmpty ? 1 : 0;
    if (fileAnnotations) {
      logCommander.info(message);
    }
  }
  return total;
}

/// Traverse the list of comments made by a specific user
/// and remove all.
///
/// [commentsUrl] -- The URL used to fetch the comments.
/// [userId] -- The user's account id number.
/// [commentCount] -- the number of comments to traverse via REST API.
/// [deletePost] -- A flag to actually delete the applicable comment.
///
/// ### Returns
/// The `commentId` of the comment that was previously posted (or null in case
/// of failure).
Future<int?> removeBotComments(
  Uri commentsUrl,
  int userId,
  int commentCount,
  bool deletePost,
) async {
  log.info('commentsUrl: $commentsUrl');
  int? commentId;
  while (commentCount > 0) {
    var response = await requests.get(commentsUrl);
    if (response.statusCode != 200) {
      return null; // error getting comments for the thread; stop here
    }
    var comments = jsonDecode(response.body) as List<Map<String, Object>>;
    commentCount -= comments.length;
    for (final comment in comments) {
      // only search for comments from the user's ID and
      // whose comment body begins with a specific html comment
      var commentUser = comment['user'] as Map<String, Object>;
      if (commentUser['id'] as int == userId &&
          // the specific html comment is our action's name
          (comment['body'] as String)
              .startsWith('<!-- cpp linter action -->')) {
        if (deletePost || (!deletePost && commentId != null)) {
          // remove outdated comments (if not updating it), but
          // don't remove the first comment if only updating the comment
          var commentUrl = Uri.dataFromString(comment['url'] as String);
          response = await requests.delete(commentUrl, headers: makeHeaders());
          log.info(
            'Got ${response.statusCode} from DELETE ${commentUrl.path}',
          );
          logRequestResponse(response);
        }
        commentId = comment['id'] as int;
      }
      // log.config(
      //   'comment id ${comment['id']} from user ${commentUser['login']} '
      //   '(${commentUser['id']})',
      // );
    }
    await File('.cpp_linter_cache/comments.json')
        .writeAsString(comments.toString(), mode: FileMode.append);
  }
  return commentId;
}

/// Update a thread comment.
///
/// - [comment] The new comment body (could be empty if strictly removing an
///   outdated comment).
/// - [userId] -- The user's account ID number.
/// - [commentsUrl] -- The url used to interact with the REST API via http
///   requests.
/// - [commentCount] -- The number of previous/outdated comment to traverse.
/// - [updateOnly] -- This flag allows  only updating the first comment in the
/// event's thread (other multiple comments made with [userId] will be removed).
Future<void> updateComment(
  String comment,
  int userId,
  Uri commentsUrl,
  int commentCount,
  bool updateOnly,
) async {
  final commentId = await removeBotComments(
    commentsUrl,
    userId,
    commentCount,
    comment.isEmpty ? false : updateOnly,
  );
  if (comment.isNotEmpty) {
    var payload = jsonEncode({'body': comment});
    log.config('payload body:\n$payload');
    final requests.Response response;
    if (updateOnly && commentId != null) {
      commentsUrl = Uri(
        scheme: ghApiUri.first,
        host: ghApiUri.last,
        path: '${commentsUrl.path}/$commentId',
      );
      response = await requests.patch(
        commentsUrl,
        headers: makeHeaders(),
        body: payload,
      );
      log.info('Got ${response.statusCode} from PATCHing comment');
    } else {
      response = await requests.post(
        commentsUrl,
        headers: makeHeaders(),
        body: payload,
      );
      log.info('Got ${response.statusCode} from POSTing comment');
    }
    logRequestResponse(response);
  }
}

/// POST action's results for a push event.
///
/// - [baseUri] -- The root of the url used to interact with the REST API via
/// http requests.
/// - [userId] -- The user's account ID number.
/// - [comment] -- The Markdown comment to post.
/// - [updateOnly] -- This flag allows  only updating the first comment in the
/// event's thread (other multiple comments made with [userId] will be removed).
///
/// ### Returns
/// A bool describing if any failures were encountered.
Future<bool> postPrComment(
    String baseUri, int userId, String comment, bool updateOnly) async {
  baseUri = '${baseUri}issues/${ghEventPayload['number']}';
  var commentsUrl = Uri(
    scheme: ghApiUri.first,
    host: ghApiUri.last,
    path: '$baseUri/comments',
  );
  var response = await requests.get(
    Uri(
      scheme: ghApiUri.first,
      host: ghApiUri.last,
      path: baseUri,
    ),
    headers: makeHeaders(),
  );
  logRequestResponse(response);
  final int commentCount;
  if (response.statusCode == 200) {
    commentCount = (jsonDecode(response.body) as Map<String, int>)['comments']!;
  } else {
    return false;
  }
  await updateComment(comment, userId, commentsUrl, commentCount, !updateOnly);
  return true;
}

/// POST action's results for a push event.
///
/// - [baseUri] -- The root of the url used to interact with the REST API via
/// http requests.
/// - [userId] -- The user's account ID number.
/// - [comment] -- The Markdown comment to post.
/// - [updateOnly] -- This flag allows  only updating the first comment in the
/// event's thread (other multiple comments made with [userId] will be removed).
///
/// ### Returns
/// A bool describing if any failures were encountered.
Future<bool> postPushComment(
    String baseUri, int userId, String comment, bool updateOnly) async {
  baseUri = '${baseUri}commits/$githubSha';
  final commentsUrl = Uri(
    scheme: ghApiUri.first,
    host: ghApiUri.last,
    path: '$baseUri/comments',
  );
  var response = await requests.get(
    Uri(
      scheme: ghApiUri.first,
      host: ghApiUri.last,
      path: baseUri,
    ),
    headers: makeHeaders(),
  );
  logRequestResponse(response);
  final int commentCount;
  if (response.statusCode == 200) {
    commentCount = (jsonDecode(response.body)
        as Map<String, Map<String, int>>)['commit']!['comment_count']!;
  } else {
    return false;
  }
  await updateComment(comment, userId, commentsUrl, commentCount, !updateOnly);
  return true;
}

/// Post action's results using REST API.
///
/// [comment] -- The comment to post (could be an empty string if only
/// deleting/updating a comment).
/// [updateOnly] -- This flag allows  only updating the first comment in the
/// event's thread (other multiple comments made with [userId] will be removed).
/// [userId] -- The user's account ID number. Defaults to the generic bot's ID.
Future<void> postResults(
  String comment,
  bool updateOnly, {
  int userId = 41898282,
}) async {
  if (githubToken.isNotEmpty) {
    log.severe('The GITHUB_TOKEN is required!');
    setExitCode(1);
    assert(githubToken.isNotEmpty);
  }
  final baseUri = '/repos/$githubRepository/';
  var checksPassed = true;
  if (githubEventName == 'pull_request') {
    checksPassed = await postPrComment(baseUri, userId, comment, updateOnly);
  } else if (githubEventName == 'push') {
    checksPassed = await postPushComment(baseUri, userId, comment, updateOnly);
  }
  setExitCode(checksPassed ? 1 : 0);
}
