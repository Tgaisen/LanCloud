import 'app_log.dart';

typedef WebViewLogWriter = void Function(String message);

/// Low-volume WebView lifecycle breadcrumbs.
///
/// Only the origin/host is logged, never the full URL, because share links and
/// redirect targets can contain access tokens or passwords.
class WebViewDiagnostics {
  WebViewDiagnostics({required this.name, WebViewLogWriter? writer})
    : _writer = writer ?? _writeToAppLog;

  static const _progressMilestones = <int>[25, 50, 75, 100];

  final String name;
  final WebViewLogWriter _writer;
  final Set<int> _loggedProgress = <int>{};

  void opened(String url) {
    _write('opened endpoint=${endpointLabel(url)}');
  }

  void created() {
    _write('created');
  }

  void loadRequested(String url) {
    _write('load-requested endpoint=${endpointLabel(url)}');
  }

  void loadStarted(String? url) {
    _write('load-started endpoint=${endpointLabel(url)}');
  }

  void progress(int percent) {
    for (final milestone in _progressMilestones) {
      if (percent >= milestone && _loggedProgress.add(milestone)) {
        _write('progress=$milestone%');
      }
    }
  }

  void loadStopped(String? url) {
    _write('load-stopped endpoint=${endpointLabel(url)}');
  }

  void loadFailed(String? url, Object code, String description) {
    final detail = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    final shortened = detail.length > 200
        ? '${detail.substring(0, 200)}…'
        : detail;
    _write(
      'load-failed endpoint=${endpointLabel(url)} code=$code'
      '${shortened.isEmpty ? '' : ' detail=$shortened'}',
    );
  }

  void closed() {
    _write('closed');
  }

  void _write(String message) {
    _writer('$name: $message');
  }

  static void _writeToAppLog(String message) {
    AppLog.instance.log('webview', message);
  }

  /// A privacy-safe endpoint label for logs.
  static String endpointLabel(String? value) {
    if (value == null || value.isEmpty) return 'none';
    final uri = Uri.tryParse(value);
    if (uri == null) return 'invalid';
    if (uri.host.isNotEmpty) return uri.host;
    if (uri.scheme.isNotEmpty) return '${uri.scheme}:<hidden>';
    return 'local';
  }
}
