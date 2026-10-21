// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:reading_novels/drive_library_service.dart';
import 'package:reading_novels/main.dart';
import 'package:reading_novels/reading_progress_store.dart';

void main() {
  testWidgets('requires Google sign-in before opening the library', (WidgetTester tester) async {
    await tester.pumpWidget(const ReadingNovelsApp());
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Your library'), findsNothing);
  });

  test('imports EPUB files but excludes PDFs', () {
    const epub = DriveEntry(id: 'epub', name: 'novel.epub', mimeType: 'application/epub+zip');
    const pdf = DriveEntry(id: 'pdf', name: 'manual.pdf', mimeType: 'application/pdf');

    expect(epub.isBook, isTrue);
    expect(pdf.isBook, isFalse);
  });

  test('calculates progress from the current EPUB position', () {
    const progress = ReadingProgress(currentSection: 3, totalSections: 8, fraction: 0.5);

    expect(progress.value, closeTo(0.3125, 0.000001));
  });
}
