import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
    if (!isConfigured) return null;
    return _client.silentSignIn();
  }

  Future<GoogleSignInCredentials?> signIn() => _client.signIn();

  Future<void> signOut() async {
    if (isConfigured) await _client.signOut();
  }

  Future<http.Client?> get authenticatedClient async {
    if (!isConfigured) return null;
    if (kIsWeb) {
      final accessToken = await drive_access
          .requestDriveAccessToken(clientId, driveScope)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
              'Google Drive authorization timed out. Allow the Google popup and try again.',
            ),
          );
      return _DriveAccessClient(accessToken);
    }
    return _client.authenticatedClient;
  }

  Widget? webSignInButton(
      {required ValueChanged<GoogleSignInCredentials> onSignIn}) {
    if (!kIsWeb || !isConfigured) return null;
    return _client.signInButton(
      config: GSIAPButtonConfig(onSignIn: onSignIn),
    );
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
