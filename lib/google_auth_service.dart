import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  static const clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET');
  static const driveScope = 'https://www.googleapis.com/auth/drive.readonly';

  GoogleSignIn? _googleSignIn;

  Stream<GoogleSignInCredentials?> get authenticationState => _client.authenticationState;

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
    return _client.authenticatedClient;
  }

  Widget? get webSignInButton {
    if (!kIsWeb || !isConfigured) return null;
    return _client.signInButton();
  }
}