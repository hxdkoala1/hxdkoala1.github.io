// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:reading_novels/local_library_store.dart';
import 'package:reading_novels/main.dart';
import 'package:reading_novels/reading_progress_store.dart';

class _MemoryLibraryStore extends LocalLibraryStore {
  @override
  Future<void> open() async {}

  @override
  List<StoredEpub> loadAll() => const [];

  @override
  Future<void> save(StoredEpub book, Uint8List bytes) async {}
}

void main() {
  testWidgets('opens the library with local EPUB import',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ReadingNovelsApp(libraryStore: _MemoryLibraryStore()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your library'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  test('local EPUB book uses its filename and stable ID', () {
    final book = Book.fromStored(
      StoredEpub(
        id: 'content-hash',
        fileName: 'novel.epub',
      ),
      0,
    );

    expect(book.id, 'content-hash');
    expect(book.title, 'novel');
    expect(book.genre, 'EPUB');
  });

  test('calculates progress from the current EPUB position', () {
    const progress =
        ReadingProgress(currentSection: 3, totalSections: 8, fraction: 0.5);

    expect(progress.value, closeTo(0.3125, 0.000001));
  });
}
