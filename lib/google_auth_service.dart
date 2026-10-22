import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:http/http.dart' as http;

import 'google_drive_access_stub.dart'
    if (dart.library.html) 'google_drive_access_web.dart' as drive_access;

class GoogleAuthService {
  static const clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const clientSecret =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET');
  static const driveScope = 'https://www.googleapis.com/auth/drive.readonly';

  GoogleSignIn? _googleSignIn;
  String? _webAccessToken;
  DateTime? _webAccessTokenExpiresAt;

  Stream<GoogleSignInCredentials?> get authenticationState =>
      _client.authenticationState;

  bool get isConfigured {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return clientId.isNotEmpty && (!desktop || clientSecret.isNotEmpty);
  }

  GoogleSignIn get _client {
    if (!isConfigured) {
      throw StateError('Google OAuth is not configured for this platform.');
    }
    return _googleSignIn ??= GoogleSignIn(
      params: const GoogleSignInParams(
        clientId: clientId,
        clientSecret: clientSecret,
        scopes: [
          'openid',
          'profile',
          'email',
          driveScope,
        ],
      ),
    );
  }

  Future<GoogleSignInCredentials?> restoreSession() async {
    if (!isConfigured || kIsWeb) return null;
    return _client.silentSignIn();
  }

  Future<GoogleSignInCredentials?> signIn() async {
    if (!isConfigured) return null;
    if (!kIsWeb) return _client.signIn();

    final accessToken = await _getWebAccessToken();
    return GoogleSignInCredentials(
      accessToken: accessToken,
      scopes: const [driveScope],
      expiresIn: _webAccessTokenExpiresAt,
    );
  }

  Future<void> signOut() async {
    _webAccessToken = null;
    _webAccessTokenExpiresAt = null;
    if (isConfigured && !kIsWeb) await _client.signOut();
  }

  Future<http.Client?> get authenticatedClient async {
    if (!isConfigured) return null;
    if (kIsWeb) {
      return _DriveAccessClient(await _getWebAccessToken());
    }
    return _client.authenticatedClient;
  }

  Future<String> _getWebAccessToken() async {
    final currentToken = _webAccessToken;
    final expiresAt = _webAccessTokenExpiresAt;
    if (currentToken != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return currentToken;
    }

    final accessToken = await drive_access
        .requestDriveAccessToken(clientId, driveScope)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Google did not return from the authorization window within 30 seconds.',
          ),
        );
    _webAccessToken = accessToken;
    _webAccessTokenExpiresAt = DateTime.now().add(const Duration(minutes: 50));
    return accessToken;
  }
}

class _DriveAccessClient extends http.BaseClient {
  _DriveAccessClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
