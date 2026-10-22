import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DriveEntry {
  const DriveEntry({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
  });

  final String id;
  final String name;
  final String mimeType;
  final int? size;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  bool get isBook {
    final name = this.name.toLowerCase();
    return mimeType == 'application/epub+zip' || name.endsWith('.epub');
  }

  String get format => 'EPUB';
}

class DriveLibraryService {
  const DriveLibraryService(this._client);

  final http.Client _client;

  Future<List<DriveEntry>> listChildren(String folderId) async {
    final entries = <DriveEntry>[];
    String? pageToken;

    do {
      final query =
          "'${folderId.replaceAll("'", r"\'")}' in parents and trashed = false";
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'pageSize': '1000',
        'orderBy': 'name',
        'fields': 'nextPageToken,files(id,name,mimeType,size)',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              'Google Drive did not respond within 20 seconds. Check the connection and retry.',
            ),
          );
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          401 =>
            'Google Drive authorization expired. Choose the folder again to reconnect.',
          403 =>
            'Google Drive denied access. Enable the Drive API in Google Cloud and make sure this Google account can access the folder.',
          _ =>
            'Google Drive could not list this folder (${response.statusCode}).',
        };
        final details = _driveErrorDetails(response.body);
        throw Exception(
          details == null ? message : '$message Details: $details',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final files = body['files'] as List<dynamic>? ?? const [];
      entries.addAll(files.map((file) {
        final item = file as Map<String, dynamic>;
        return DriveEntry(
          id: item['id'] as String,
          name: item['name'] as String? ?? 'Untitled',
          mimeType: item['mimeType'] as String? ?? '',
          size: int.tryParse(item['size']?.toString() ?? ''),
        );
      }));
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);

    return entries;
  }

  Future<Uint8List> download(DriveEntry entry) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${Uri.encodeComponent(entry.id)}',
      {'alt': 'media'},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Could not download ${entry.name} (${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}

String? _driveErrorDetails(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final error = decoded['error'];
    if (error is! Map) return null;

    final errors = error['errors'];
    final firstError =
        errors is List && errors.isNotEmpty ? errors.first : null;
    final reason = firstError is Map ? firstError['reason'] : null;
    final message = error['message'];
    final details = [
      if (reason is String && reason.isNotEmpty) reason,
      if (message is String && message.isNotEmpty) message,
    ];
    return details.isEmpty ? null : details.join(': ');
  } on FormatException {
    return null;
  }
}
