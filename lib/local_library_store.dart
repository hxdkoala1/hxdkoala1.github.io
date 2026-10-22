import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';

class StoredEpub {
  const StoredEpub({
    required this.id,
    required this.fileName,
  });

  final String id;
  final String fileName;
}

class LocalLibraryStore {
  static const _libraryBoxName = 'local_epub_library_v1';
  static const _bytesBoxName = 'local_epub_bytes_v1';

  Box<String>? _libraryBox;
  Box<String>? _bytesBox;

  Future<void> open() async {
    await Hive.initFlutter();
    _libraryBox = await Hive.openBox<String>(_libraryBoxName);
    _bytesBox = await Hive.openBox<String>(_bytesBoxName);
  }

  List<StoredEpub> loadAll() {
    final libraryBox = _libraryBox;
    if (libraryBox == null) {
      throw StateError('The local library is not open.');
    }

    return [
      for (final entry in libraryBox.toMap().entries)
        _decode(entry.key, entry.value),
    ];
  }

  Future<Uint8List> loadBytes(String id) async {
    final bytesBox = _bytesBox;
    if (bytesBox == null) throw StateError('The local library is not open.');
    final encoded = bytesBox.get(id);
    if (encoded == null) throw StateError('The EPUB file is missing locally.');
    return Uint8List.fromList(base64Decode(encoded));
  }

  Future<void> save(StoredEpub book, Uint8List bytes) async {
    final libraryBox = _libraryBox;
    final bytesBox = _bytesBox;
    if (libraryBox == null || bytesBox == null) {
      throw StateError('The local library is not open.');
    }

    await bytesBox.put(book.id, base64Encode(bytes));
    await libraryBox.put(
      book.id,
      jsonEncode({
        'fileName': book.fileName,
      }),
    );
  }

  StoredEpub _decode(String id, String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    return StoredEpub(
      id: id,
      fileName: record['fileName'] as String,
    );
  }
}
