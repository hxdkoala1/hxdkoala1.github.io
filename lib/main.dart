import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:epub_view/epub_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' show parse;

import 'local_library_store.dart';
import 'reading_progress_store.dart';

void main() {
  runApp(ReadingNovelsApp());
}

const _ink = Color(0xFF202820);
const _paper = Color(0xFFF5F2EA);
const _green = Color(0xFF315747);
const _coral = Color(0xFFB64D3E);

class Book {
  const Book({
    required this.id,
    required this.fileName,
    required this.coverColor,
  });

  factory Book.fromStored(StoredEpub epub, int index) => Book(
        id: epub.id,
        fileName: epub.fileName,
        coverColor: _coverColors[index % _coverColors.length],
      );

  final String id;
  final String fileName;
  final Color coverColor;

  String get title =>
      fileName.replaceFirst(RegExp(r'\.epub$', caseSensitive: false), '');
  String get author => 'Local EPUB';
  int get year => 0;
  int get pages => 0;
  String get genre => 'EPUB';
  String get description => 'Imported from this device.';
}

const _coverColors = [
  Color(0xFFB8C9B0),
  Color(0xFFD6B36B),
  Color(0xFFB77869),
  Color(0xFF78949A),
  Color(0xFF9EAA85),
  Color(0xFFC58A64),
];

class ReadingNovelsApp extends StatefulWidget {
  ReadingNovelsApp({super.key, LocalLibraryStore? libraryStore})
      : libraryStore = libraryStore ?? LocalLibraryStore();

  final LocalLibraryStore libraryStore;

  @override
  State<ReadingNovelsApp> createState() => _ReadingNovelsAppState();
}

class _ReadingNovelsAppState extends State<ReadingNovelsApp> {
  final _progressStore = ReadingProgressStore();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  LocalLibraryStore get _libraryStore => widget.libraryStore;

  int _destination = 0;
  String _query = '';
  String _fontFamily = 'serif';
  Color _pageColor = const Color(0xFFF7F1E3);
  Book? _readingBook;
  List<Book> _books = [];
  Map<String, ReadingProgress> _progress = {};
  Uint8List? _readerBytes;
  String? _libraryError;
  bool _libraryLoading = true;
  bool _importBusy = false;
  bool _readerBusy = false;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      await _libraryStore.open();
      final storedBooks = _libraryStore.loadAll();
      final progress = await _progressStore.loadAll();
      if (!mounted) return;
      setState(() {
        _books = [
          for (var i = 0; i < storedBooks.length; i++)
            Book.fromStored(storedBooks[i], i),
        ];
        _progress = progress;
      });
    } catch (error) {
      _libraryError = 'Could not load the local library: $error';
    }
    if (mounted) {
      setState(() => _libraryLoading = false);
    }
  }

  Future<void> _importEpubs() async {
    if (_importBusy) return;
    setState(() {
      _importBusy = true;
      _libraryError = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (files.isEmpty) return;

      final imported = <String, Book>{for (final book in _books) book.id: book};
      for (final file in files) {
        if (!file.name.toLowerCase().endsWith('.epub')) continue;
        final bytes = await file.readAsBytes();
        final id = crypto.sha256.convert(bytes).toString();
        final stored = StoredEpub(id: id, fileName: file.name);
        await _libraryStore.save(stored, bytes);
        imported[id] = Book.fromStored(stored, imported.length);
      }
      if (!mounted) return;
      setState(() {
        _books = imported.values.toList();
        _query = '';
      });
      _showMessage('EPUB files imported to this device.');
    } catch (error) {
      if (mounted) {
        setState(() => _libraryError = 'Could not import EPUB files: $error');
      }
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Future<void> _openReader(Book book) async {
    setState(() {
      _readingBook = book;
      _readerBytes = null;
      _readerBusy = true;
      _destination = 1;
    });
    try {
      final bytes = await _libraryStore.loadBytes(book.id);
      if (mounted) setState(() => _readerBytes = bytes);
    } catch (error) {
      if (mounted) {
        setState(() => _destination = 0);
        _showMessage('Could not open ${book.title}: $error');
      }
    } finally {
      if (mounted) setState(() => _readerBusy = false);
    }
  }

  void _saveProgress(Book book, ReadingProgress progress) {
    setState(() => _progress[book.id] = progress);
    unawaited(_progressStore.save(book.id, progress));
  }

  void _showMessage(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _green,
        surface: _paper,
        primary: _green,
        secondary: _coral,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _paper,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: _ink,
            displayColor: _ink,
          ),
    );

    return MaterialApp(
      title: 'Reading Novels',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: theme,
      home: _libraryLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 850;
                return Scaffold(
                  body: SafeArea(
                    child: Row(
                      children: [
                        if (desktop)
                          _SideNavigation(
                            selectedIndex: _destination,
                            bookCount: _books.length,
                            onSelected: (index) => setState(() {
                              _destination = index;
                            }),
                          ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _buildPage(desktop),
                          ),
                        ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: desktop
                      ? null
                      : NavigationBar(
                          selectedIndex: _destination,
                          onDestinationSelected: (index) => setState(() {
                            _destination = index;
                          }),
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.auto_stories_outlined),
                              selectedIcon: Icon(Icons.auto_stories),
                              label: 'Library',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.menu_book_outlined),
                              selectedIcon: Icon(Icons.menu_book),
                              label: 'Read',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.tune_outlined),
                              selectedIcon: Icon(Icons.tune),
                              label: 'Settings',
                            ),
                          ],
                        ),
                );
              },
            ),
    );
  }

  Widget _buildPage(bool desktop) {
    if (_destination == 1) {
      return _ReaderPage(
        key: const ValueKey('reader'),
        book: _readingBook,
        bytes: _readerBytes,
        loading: _readerBusy,
        progress: _readingBook == null ? null : _progress[_readingBook!.id],
        fontFamily: _fontFamily,
        pageColor: _pageColor,
        onCustomize: _showReaderSettings,
        onProgressChanged: (progress) {
          final book = _readingBook;
          if (book != null) _saveProgress(book, progress);
        },
        onBrowse: () => setState(() => _destination = 0),
      );
    }
    if (_destination == 2) {
      return _SettingsPage(
        key: const ValueKey('settings'),
        fontFamily: _fontFamily,
        pageColor: _pageColor,
        onFontChanged: (value) => setState(() => _fontFamily = value),
        onColorChanged: (value) => setState(() => _pageColor = value),
      );
    }
    return _LibraryPage(
      key: const ValueKey('library'),
      desktop: desktop,
      books: _books,
      progress: _progress,
      importBusy: _importBusy,
      error: _libraryError,
      query: _query,
      onQueryChanged: (value) => setState(() => _query = value),
      onOpenBook: _showBookDetails,
      onImport: _importEpubs,
    );
  }

  void _showBookDetails(Book book) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (context) => _BookDetailsSheet(
        book: book,
        progress: _progress[book.id],
        onRead: () {
          Navigator.pop(context);
          unawaited(_openReader(book));
        },
      ),
    );
  }

  void _showReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _paper,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => _ReaderControls(
          fontFamily: _fontFamily,
          pageColor: _pageColor,
          onFontChanged: (value) {
            setState(() => _fontFamily = value);
            setSheetState(() {});
          },
          onColorChanged: (value) {
            setState(() => _pageColor = value);
            setSheetState(() {});
          },
        ),
      ),
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation(
      {required this.selectedIndex,
      required this.bookCount,
      required this.onSelected});

  final int selectedIndex;
  final int bookCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        width: 224,
        padding: const EdgeInsets.fromLTRB(22, 24, 14, 18),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE3DED3))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 38),
              child: Row(
                children: [
                  Icon(Icons.auto_stories, color: _green, size: 27),
                  SizedBox(width: 10),
                  Text(
                    'Reading Novels',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            _NavItem(
              icon: Icons.auto_stories_outlined,
              label: 'Library',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              label: 'Read now',
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _NavItem(
              icon: Icons.tune_outlined,
              label: 'Settings',
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Text(
                'YOUR SHELF',
                style: TextStyle(
                  color: Color(0xFF77796F),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('$bookCount books',
                  style: const TextStyle(color: Color(0xFF77796F))),
            ),
          ],
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: ListTile(
          leading: Icon(icon, size: 21),
          title: Text(label, style: const TextStyle(fontSize: 14)),
          selected: selected,
          selectedColor: _green,
          selectedTileColor: const Color(0xFFE4EAE0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: onTap,
        ),
      );
}

class _LibraryPage extends StatelessWidget {
  const _LibraryPage({
    super.key,
    required this.desktop,
    required this.books,
    required this.progress,
    required this.importBusy,
    required this.error,
    required this.query,
    required this.onQueryChanged,
    required this.onOpenBook,
    required this.onImport,
  });

  final bool desktop;
  final List<Book> books;
  final Map<String, ReadingProgress> progress;
  final bool importBusy;
  final String? error;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final results = books
        .where((book) => '${book.title} ${book.author} ${book.genre}'
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();

    return SingleChildScrollView(
      padding:
          EdgeInsets.symmetric(horizontal: desktop ? 46 : 20, vertical: 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your library',
                            style: TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w700)),
                        SizedBox(height: 5),
                        Text('Your books, ready when you are.',
                            style: TextStyle(color: Color(0xFF77796F))),
                      ],
                    ),
                  ),
                  if (desktop) ...[
                    OutlinedButton.icon(
                      onPressed: importBusy ? null : onImport,
                      icon: importBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_open_outlined, size: 18),
                      label: Text(importBusy ? 'Importing...' : 'Import Files'),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
              if (!desktop) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: importBusy ? null : onImport,
                    icon: importBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(importBusy ? 'Importing...' : 'Import Files'),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                SelectableText(error!),
              ],
              const SizedBox(height: 25),
              TextField(
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search title, author, or genre',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFECE8DE),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Expanded(
                    child: Text('On your shelf',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  Text('${results.length} titles',
                      style: const TextStyle(color: Color(0xFF77796F))),
                ],
              ),
              const SizedBox(height: 18),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      books.isEmpty
                          ? 'Import EPUB files to fill your library.'
                          : 'No books match that search.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: results.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 205,
                      mainAxisExtent: 340,
                      crossAxisSpacing: desktop ? 24 : 14,
                      mainAxisSpacing: 24,
                    ),
                    itemBuilder: (context, index) => _BookTile(
                      book: results[index],
                      progress: progress[results[index].id],
                      onTap: () => onOpenBook(results[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile(
      {required this.book, required this.progress, required this.onTap});

  final Book book;
  final ReadingProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _BookCover(book: book)),
            const SizedBox(height: 10),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF77796F)),
            ),
            const SizedBox(height: 3),
            Text(book.genre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF77796F))),
            if (progress?.hasStarted ?? false) ...[
              const SizedBox(height: 7),
              LinearProgressIndicator(value: progress!.value, minHeight: 4),
              const SizedBox(height: 3),
              Text('${(progress!.value * 100).round()}% complete',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF77796F))),
            ],
          ],
        ),
      );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: book.coverColor,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -25,
              bottom: -30,
              child: Icon(Icons.circle_outlined,
                  size: 150, color: Colors.white.withValues(alpha: 0.18)),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.genre.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.7),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.auto_stories_outlined,
                      size: 23, color: _ink.withValues(alpha: 0.72)),
                  const SizedBox(height: 11),
                  Text(
                    book.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontFamily: 'serif',
                      fontSize: 21,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _ink.withValues(alpha: 0.8), fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BookDetailsSheet extends StatelessWidget {
  const _BookDetailsSheet(
      {required this.book, required this.progress, required this.onRead});

  final Book book;
  final ReadingProgress? progress;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 140, height: 205, child: _BookCover(book: book)),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(book.genre.toUpperCase(),
                            style: const TextStyle(
                                color: _coral,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(book.title,
                            style: const TextStyle(
                                fontSize: 23, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(book.author,
                            style: const TextStyle(color: Color(0xFF77796F))),
                        const SizedBox(height: 15),
                        Text(book.genre),
                        const SizedBox(height: 12),
                        Text(book.description,
                            style: const TextStyle(height: 1.45)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Reading progress',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              progress?.hasStarted == true
                                  ? '${(progress!.value * 100).round()}%'
                                  : 'Not started',
                              style: const TextStyle(color: Color(0xFF77796F)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress?.value ?? 0),
                        if (progress != null &&
                            progress!.totalSections > 0) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Section ${progress!.currentSection} of ${progress!.totalSections}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF77796F)),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onRead,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(progress?.hasStarted == true
                              ? 'Continue reading'
                              : 'Start reading'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ReaderPage extends StatefulWidget {
  const _ReaderPage({
    super.key,
    required this.book,
    required this.bytes,
    required this.loading,
    required this.progress,
    required this.fontFamily,
    required this.pageColor,
    required this.onCustomize,
    required this.onProgressChanged,
    required this.onBrowse,
  });

  final Book? book;
  final Uint8List? bytes;
  final bool loading;
  final ReadingProgress? progress;
  final String fontFamily;
  final Color pageColor;
  final VoidCallback onCustomize;
  final ValueChanged<ReadingProgress> onProgressChanged;
  final VoidCallback onBrowse;

  @override
  State<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<_ReaderPage> {
  EpubController? _epubController;
  int _totalChapters = 1;
  List<int> _sectionLengths = const [];

  @override
  void initState() {
    super.initState();
    _createEpubController();
  }

  @override
  void didUpdateWidget(covariant _ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.book?.id != widget.book?.id) {
      _epubController = null;
      _createEpubController();
    }
  }

  void _createEpubController() {
    final book = widget.book;
    final bytes = widget.bytes;
    if (book != null && bytes != null) {
      _epubController = EpubController(
        document: EpubDocument.openData(bytes),
        epubCfi: widget.progress?.epubCfi,
      );
    }
  }

  Widget _buildDocument() {
    final bytes = widget.bytes;
    final book = widget.book;
    if (widget.loading || bytes == null || book == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final controller = _epubController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return EpubView(
      controller: controller,
      onDocumentLoaded: (document) {
        final chapters = <EpubChapter>[];
        for (final chapter in document.Chapters ?? const <EpubChapter>[]) {
          chapters
            ..add(chapter)
            ..addAll(chapter.SubChapters ?? const <EpubChapter>[]);
        }
        _totalChapters = chapters.length;
        _sectionLengths = chapters.map(_sectionLength).toList();
      },
      onChapterChanged: (value) {
        if (value == null || value.chapterNumber < 1) return;
        final sectionIndex = value.chapterNumber - 1;
        final length = sectionIndex < _sectionLengths.length
            ? _sectionLengths[sectionIndex]
            : 0;
        final sectionProgress = length > 0
            ? ((value.paragraphNumber - 1 + value.progress / 100) / length)
                .clamp(0.0, 1.0)
            : (value.progress / 100).clamp(0.0, 1.0);
        widget.onProgressChanged(ReadingProgress(
          currentSection: value.chapterNumber,
          totalSections: _totalChapters,
          fraction: sectionProgress,
          epubCfi: controller.generateEpubCfi(),
        ));
      },
      onDocumentError: (error) {
        if (error != null) _showReaderError(error.toString());
      },
    );
  }

  int _sectionLength(EpubChapter chapter) {
    final body = parse(chapter.HtmlContent ?? '').body;
    if (body == null) return 0;
    final elements = _flattenElements(body.children.toList());
    final anchor = chapter.Anchor;
    if (anchor == null) return elements.length;
    final start = elements
        .indexWhere((element) => element.outerHtml.contains('id="$anchor"'));
    return start < 0 ? elements.length : elements.length - start;
  }

  List<html.Element> _flattenElements(List<html.Element> elements) => [
        for (final element in elements)
          if (element.localName == 'div' && element.children.length > 1)
            ..._flattenElements(element.children.toList())
          else
            element,
      ];

  void _showReaderError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read this book: $message')));
  }

  @override
  Widget build(BuildContext context) {
    final currentBook = widget.book;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              IconButton(
                  tooltip: 'Back to library',
                  onPressed: widget.onBrowse,
                  icon: const Icon(Icons.arrow_back)),
              const Spacer(),
              Text(currentBook?.title ?? 'Reading room',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                  tooltip: 'Reader appearance',
                  onPressed: widget.onCustomize,
                  icon: const Icon(Icons.tune)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: widget.pageColor,
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: _buildDocument(),
          ),
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    super.key,
    required this.fontFamily,
    required this.pageColor,
    required this.onFontChanged,
    required this.onColorChanged,
  });

  final String fontFamily;
  final Color pageColor;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
        children: [
          const Text('Settings',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Make your reading space feel like yours.',
              style: TextStyle(color: Color(0xFF77796F))),
          const SizedBox(height: 32),
          const Text('READER APPEARANCE',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _green)),
          const SizedBox(height: 15),
          _ReaderControls(
            fontFamily: fontFamily,
            pageColor: pageColor,
            onFontChanged: onFontChanged,
            onColorChanged: onColorChanged,
          ),
        ],
      );
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.fontFamily,
    required this.pageColor,
    required this.onFontChanged,
    required this.onColorChanged,
  });

  final String fontFamily;
  final Color pageColor;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;

  static const _pageColors = [
    Color(0xFFF7F1E3),
    Color(0xFFFFFFFF),
    Color(0xFF29312D),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Reading appearance',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 23),
            const Text('TYPEFACE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF77796F))),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'serif', label: Text('Serif')),
                ButtonSegment(value: 'sans-serif', label: Text('Sans')),
                ButtonSegment(value: 'monospace', label: Text('Mono')),
              ],
              selected: {fontFamily},
              onSelectionChanged: (selection) => onFontChanged(selection.first),
            ),
            const SizedBox(height: 23),
            const Text('PAGE COLOR',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF77796F))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                for (final color in _pageColors)
                  Semantics(
                    button: true,
                    label: color == _pageColors[0]
                        ? 'Warm paper'
                        : color == _pageColors[1]
                            ? 'White'
                            : 'Night',
                    child: InkWell(
                      onTap: () => onColorChanged(color),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: pageColor == color
                                ? _green
                                : const Color(0xFFCBC6BC),
                            width: pageColor == color ? 3 : 1,
                          ),
                        ),
                        child: pageColor == color
                            ? Icon(Icons.check,
                                size: 18,
                                color: color == _pageColors[2]
                                    ? Colors.white
                                    : _green)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}
