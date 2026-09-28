import '../services/ha_exception.dart';

class ConnectionConfig {
  const ConnectionConfig._(this.uri, this.token);
  factory ConnectionConfig(String url, String token) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.host.contains(RegExp(r'\s')) ||
        uri.port <= 0 ||
        uri.port > 65535) {
      throw const HaException(
        HaError.invalidUrl,
        'Enter a valid Home Assistant origin, such as http://192.168.1.10:8123 (no path or credentials).',
      );
    }
    if (token.trim().isEmpty || token.contains(RegExp(r'\s'))) {
      throw const HaException(
        HaError.unauthorized,
        'Enter a valid long-lived access token.',
      );
    }
    return ConnectionConfig._(uri.replace(path: ''), token.trim());
  }
  final Uri uri;
  final String token;
  String get url => uri.toString();
  Uri endpoint(String path) => uri.replace(path: path);
  Uri get websocketUri => uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '/api/websocket',
  );
  @override
  String toString() => 'ConnectionConfig(credentials redacted)';
}
