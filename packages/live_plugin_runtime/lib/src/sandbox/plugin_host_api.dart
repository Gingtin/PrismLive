import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:live_net/live_net.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_security.dart';

/// Sandboxed host API available to plugins via the `host` namespace.
class PluginHostApi {
  /// Creates a [PluginHostApi].
  new({
    required this.allowedDomains,
    LiveHttp? http,
    void Function(String message)? onLog,
  })  : _http = http ?? IoLiveHttp(),
        _onLog = onLog ?? _defaultLog;

  /// Whitelist of allowed domain names for network requests.
  final List<String> allowedDomains;
  final LiveHttp _http;
  final void Function(String message) _onLog;

  static void _defaultLog(String message) {
    // In production or tests, plugins can log debug info safely.
  }

  /// Sends a sandboxed HTTP GET request.
  Future<Map<String, dynamic>> httpGet(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    DomainWhitelistValidator.assertAllowed(uri, allowedDomains);

    final request = LiveRequest(
      site: 'plugin',
      url: uri,
      headers: headers ?? const {},
    );
    final response = await _http.send(request);

    return {
      'statusCode': response.status,
      'headers': response.headers,
      'body': response.text,
    };
  }

  /// Sends a sandboxed HTTP POST request.
  Future<Map<String, dynamic>> httpPost(
    String url, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final uri = Uri.parse(url);
    DomainWhitelistValidator.assertAllowed(uri, allowedDomains);

    List<int>? bodyBytes;
    if (body is List<int>) {
      bodyBytes = body;
    } else if (body is String) {
      bodyBytes = utf8.encode(body);
    } else if (body != null) {
      bodyBytes = utf8.encode(jsonEncode(body));
    }

    final request = LiveRequest(
      site: 'plugin',
      url: uri,
      method: 'POST',
      headers: headers ?? const {},
      body: bodyBytes,
    );
    final response = await _http.send(request);

    return {
      'statusCode': response.status,
      'headers': response.headers,
      'body': response.text,
    };
  }

  /// Computes MD5 hash in hex string.
  String md5(String input) {
    return crypto.md5.convert(utf8.encode(input)).toString();
  }

  /// Computes SHA-256 hash in hex string.
  String sha256(String input) {
    return crypto.sha256.convert(utf8.encode(input)).toString();
  }

  /// Computes HMAC-SHA256 signature in hex string.
  String hmacSha256(String key, String input) {
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(key));
    return hmac.convert(utf8.encode(input)).toString();
  }

  /// Base64 encodes UTF-8 string or bytes.
  String base64Encode(dynamic input) {
    if (input is List<int>) {
      return base64.encode(input);
    }
    return base64.encode(utf8.encode(input.toString()));
  }

  /// Base64 decodes string into UTF-8 text.
  String base64Decode(String input) {
    return utf8.decode(base64.decode(input));
  }

  /// Logs a message from the plugin sandbox.
  void log(String message) {
    _onLog('[PluginLog] $message');
  }
}
