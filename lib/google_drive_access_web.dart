import 'dart:js_interop';

@JS('requestDriveAccessToken')
external JSPromise<JSString> _requestDriveAccessToken(
    JSString clientId, JSString scope);

Future<String> requestDriveAccessToken(String clientId, String scope) async =>
    (await _requestDriveAccessToken(clientId.toJS, scope.toJS).toDart).toDart;
