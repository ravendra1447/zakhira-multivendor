import 'dart:io';
import 'package:http/http.dart' as http;

// Custom HTTP client for SSL certificate bypass
class CustomHttpClient {
  static HttpClient createHttpClient() {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return httpClient;
  }
}

// HTTP override for development
class DevelopmentHttpOverrides {
  static void initialize() {
    // This is a placeholder for HTTP overrides
    // In Flutter, we'll handle this differently
  }
}

// Simple HTTP client with SSL bypass
class HttpClientWithSSLBypass {
  final HttpClient _client;

  HttpClientWithSSLBypass() : _client = HttpClient() {
    _client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }

  HttpClient get client => _client;
}

// Global HTTP client instance
HttpClientWithSSLBypass? _globalHttpClient;

HttpClientWithSSLBypass getGlobalHttpClient() {
  _globalHttpClient ??= HttpClientWithSSLBypass();
  return _globalHttpClient!;
}
