import 'dart:async';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart'
    show GoogleSignInCredentials;
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' show parse;

import 'drive_library_service.dart';
import 'google_auth_service.dart';
import 'reading_progress_store.dart';

void main() {
  runApp(const ReadingNovelsApp());
}

const _ink = Color(0xFF202820);
const _paper = Color(0xFFF5F2EA);
const _green = Color(0xFF315747);
const _coral = Color(0xFFB64D3E);

class Book {
  const Book({required this.driveEntry, required this.coverColor});

  factory Book.fromDrive(DriveEntry entry, int index) => Book(
      driveEntry: entry, coverColor: _coverColors[index % _coverColors.length]);

  final DriveEntry driveEntry;
  final Color coverColor;

  String get title => driveEntry.name;
  String get author => 'Google Drive';
  int get year => 0;
  int get pages => 0;
  String get genre => driveEntry.format;
  String get description => 'Stored in the selected Google Drive folder.';
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
  const ReadingNovelsApp({super.key});

  @override
  State<ReadingNovelsApp> createState() => _ReadingNovelsAppState();
}

class _ReadingNovelsAppState extends State<ReadingNovelsApp> {
  final _auth = GoogleAuthService();
  final _progressStore = ReadingProgressStore();

  int _destination = 0;
  String _query = '';
  String _fontFamily = 'serif';
  Color _pageColor = const Color(0xFFF7F1E3);
  Book? _readingBook;
  List<Book> _books = [];
  Map<String, ReadingProgress> _progress = {};
  DriveLibraryService? _drive;
  Uint8List? _readerBytes;
  String? _folderName;
  String? _authError;
  bool _isSignedIn = false;
  bool _authRestoring = true;
  bool _authBusy = false;
  bool _driveBusy = false;
  String _driveStatus = '';
  bool _readerBusy = false;
  StreamSubscription<GoogleSignInCredentials?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      _progress = await _progressStore.loadAll();
    } catch (_) {
      _progress = {};
    }

    if (_auth.isConfigured && !kIsWeb) {
      try {
        _authRestoring = true;
        _authError = null;
        _authSubscription = _auth.authenticationState.listen((credentials) {
          if (mounted) setState(() => _isSignedIn = credentials != null);
        });
        final credentials = await _auth.restoreSession();
        _isSignedIn = credentials != null;
      } catch (error) {
        _authError = 'Google sign-in could not be restored: $error';
      }
    }
    if (mounted) {
      setState(() {
        _authRestoring = false;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_auth.isConfigured) return;
    setState(() {
      _authBusy = true;
      _authError = null;
    });
    try {
      final credentials = await _auth.signIn();
      if (credentials != null && mounted) {
        setState(() => _isSignedIn = true);
      }
    } catch (error) {
      _authError = 'Google sign-in failed: $error';
    } finally {
      if (mounted) {
        setState(() {
          _authBusy = false;
          _authRestoring = false;
        });
      }
    }
  }

  void _enterDriveTestMode() {
    setState(() {
      _isSignedIn = true;
      _authError = null;
    });
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _isSignedIn = false;
      _books = [];
      _drive = null;
      _folderName = null;
      _readingBook = null;
      _readerBytes = null;
      _destination = 0;
    });
  }

  Future<void> _connectDrive() async {
    setState(() {
      _driveBusy = true;
      _driveStatus = 'Waiting for Google...';
    });
    try {
      final client = await _auth.authenticatedClient;
      if (client == null) {
        throw StateError('Sign in to Google before opening Drive.');
      }
      if (!mounted) return;
      setState(() => _driveStatus = 'Loading Drive...');
      final drive = DriveLibraryService(client);
      final folder = await showDialog<DriveEntry>(
        context: context,
        builder: (context) => _DriveFolderPicker(service: drive),
      );
      if (folder == null) return;

      final files = await drive.listChildren(folder.id);
      final books =
          files.where((entry) => !entry.isFolder && entry.isBook).toList();
      if (!mounted) return;
      setState(() {
        _drive = drive;
        _folderName = folder.name;
        _books = [
          for (var i = 0; i < books.length; i++) Book.fromDrive(books[i], i)
        ];
        _query = '';
        _destination = 0;
      });
    } catch (error) {
      if (mounted) await _showDriveConnectionError(error);
    } finally {
      if (mounted) {
        setState(() {
          _driveBusy = false;
          _driveStatus = '';
        });
      }
    }
  }

  Future<void> _showDriveConnectionError(Object error) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Drive could not connect'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(error.toString()),
              const SizedBox(height: 12),
              const Text(
                'If access was denied, check that the Drive API is enabled and '
                'your Google account is listed as a test user in the OAuth consent settings.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReader(Book book) async {
    final drive = _drive;
    if (drive == null) return;
    setState(() {
      _readerBusy = true;
      _readingBook = book;
      _destination = 1;
    });
    try {
      final bytes = await drive.download(book.driveEntry);
      if (!mounted) return;
      setState(() => _readerBytes = bytes);
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
    setState(() => _progress[book.driveEntry.id] = progress);
    unawaited(_progressStore.save(book.driveEntry.id, progress));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      theme: theme,
      home: _authRestoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_isSignedIn
              ? _SignInPage(
                  configured: _auth.isConfigured,
                  busy: _authBusy,
                  error: _authError,
                  webButton: null,
                  showDriveTestAction: kIsWeb,
                  onSignIn: _signIn,
                  onDriveTest: _enterDriveTestMode,
                )
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
        progress: _readingBook == null
            ? null
            : _progress[_readingBook!.driveEntry.id],
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
        folderName: _folderName,
        driveBusy: _driveBusy,
        driveStatus: _driveStatus,
        onFontChanged: (value) => setState(() => _fontFamily = value),
        onColorChanged: (value) => setState(() => _pageColor = value),
        onConnect: _connectDrive,
      );
    }
    return _LibraryPage(
      key: const ValueKey('library'),
      desktop: desktop,
      books: _books,
      progress: _progress,
      folderName: _folderName,
      driveBusy: _driveBusy,
      driveStatus: _driveStatus,
      query: _query,
      onQueryChanged: (value) => setState(() => _query = value),
      onOpenBook: _showBookDetails,
      onConnect: _connectDrive,
      onSignOut: _signOut,
    );
  }

  void _showBookDetails(Book book) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (context) => _BookDetailsSheet(
        book: book,
        progress: _progress[book.driveEntry.id],
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

class _SignInPage extends StatelessWidget {
  const _SignInPage({
    required this.configured,
    required this.busy,
    required this.error,
    required this.webButton,
    required this.showDriveTestAction,
    required this.onSignIn,
    required this.onDriveTest,
  });

  final bool configured;
  final bool busy;
  final String? error;
  final Widget? webButton;
  final bool showDriveTestAction;
  final VoidCallback onSignIn;
  final VoidCallback onDriveTest;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories, color: _green, size: 46),
                    const SizedBox(height: 18),
                    const Text(
                      'Reading Novels',
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in with Google to open your reading library.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF77796F)),
                    ),
                    const SizedBox(height: 28),
                    if (webButton != null)
                      webButton!
                    else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: configured && !busy ? onSignIn : null,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                              busy ? 'Connecting...' : 'Continue with Google'),
                        ),
                      ),
                    if (showDriveTestAction) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onDriveTest,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open library for Drive test'),
                      ),
                    ],
                    if (!configured) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Google OAuth is not configured yet. Add the OAuth client values to the run configuration to enable sign-in.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xFF77796F), fontSize: 13),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _coral)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _DriveFolderPicker extends StatefulWidget {
  const _DriveFolderPicker({required this.service});

  final DriveLibraryService service;

  @override
  State<_DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<_DriveFolderPicker> {
  final List<DriveEntry> _path = [
    const DriveEntry(
      id: 'root',
      name: 'My Drive',
      mimeType: 'application/vnd.google-apps.folder',
    ),
  ];
  List<DriveEntry> _folders = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final children = await widget.service.listChildren(_path.last.id);
      if (!mounted) return;
      setState(
          () => _folders = children.where((entry) => entry.isFolder).toList());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFolder(DriveEntry folder) {
    setState(() => _path.add(folder));
    _loadFolders();
  }

  void _goBack() {
    if (_path.length <= 1) return;
    setState(() => _path.removeLast());
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Row(
          children: [
            if (_path.length > 1)
              IconButton(
                tooltip: 'Back to parent folder',
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
                child: Text(_path.last.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 430,
          height: 360,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _loadFolders,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _folders.isEmpty
                      ? const Center(
                          child:
                              Text('No folders here. You can use this folder.'))
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(folder.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openFolder(folder),
                            );
                          },
                        ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed:
                _loading ? null : () => Navigator.pop(context, _path.last),
            child: const Text('Use this folder'),
          ),
        ],
      );
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
    required this.folderName,
    required this.driveBusy,
    required this.driveStatus,
    required this.query,
    required this.onQueryChanged,
    required this.onOpenBook,
    required this.onConnect,
    required this.onSignOut,
  });

  final bool desktop;
  final List<Book> books;
  final Map<String, ReadingProgress> progress;
  final String? folderName;
  final bool driveBusy;
  final String driveStatus;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onConnect;
  final VoidCallback onSignOut;

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
                      onPressed: driveBusy ? null : onConnect,
                      icon: driveBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.folder_open_outlined, size: 18),
                      label: Text(driveBusy
                          ? driveStatus
                          : folderName == null
                              ? 'Choose Drive folder'
                              : 'Change folder'),
                    ),
                    const SizedBox(width: 10),
                  ],
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              if (!desktop) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: driveBusy ? null : onConnect,
                    icon: driveBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(driveBusy
                        ? driveStatus
                        : folderName == null
                            ? 'Choose Drive folder'
                            : 'Change folder'),
                  ),
                ),
              ],
              if (folderName != null) ...[
                const SizedBox(height: 12),
                Text('Drive folder: $folderName',
                    style: const TextStyle(color: Color(0xFF77796F))),
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
                          ? 'Choose a Drive folder containing EPUB books to fill your library.'
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
                      progress: progress[results[index].driveEntry.id],
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
        oldWidget.book?.driveEntry.id != widget.book?.driveEntry.id) {
      _epubController = null;
      _createEpubController();
    }
  }

  void _createEpubController() {
    final book = widget.book;
    final bytes = widget.bytes;
    if (book != null && bytes != null && book.driveEntry.format == 'EPUB') {
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
    required this.folderName,
    required this.driveBusy,
    required this.driveStatus,
    required this.onFontChanged,
    required this.onColorChanged,
    required this.onConnect,
  });

  final String fontFamily;
  final Color pageColor;
  final String? folderName;
  final bool driveBusy;
  final String driveStatus;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onConnect;

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
          const SizedBox(height: 36),
          const Text('LIBRARY SYNC',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _green)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Google Drive'),
            subtitle: Text(folderName == null
                ? 'No folder selected'
                : 'Connected to Google Drive'),
            trailing: OutlinedButton.icon(
              onPressed: driveBusy ? null : onConnect,
              icon: driveBusy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(driveBusy
                  ? driveStatus
                  : folderName == null
                      ? 'Choose'
                      : 'Change'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Books folder'),
            subtitle: Text(folderName ?? 'Choose a Drive folder'),
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
