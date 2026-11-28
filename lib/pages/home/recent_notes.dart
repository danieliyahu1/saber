import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/recent_note_visibility.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/syncing_button.dart';
import 'package:saber/components/home/welcome.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';

class const RecentPage({super.key}) extends StatefulHookWidget {
  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  final List<String> filePaths = [];

  /// Files under a locked folder that has not been unlocked: title and mark,
  /// never a preview (PRD FR-20).
  Set<String> hiddenFiles = {};

  var failed = false;

  /// The last visibility pass wins, so a slow answer cannot label a newer list.
  var _visibilityCheck = 0;

  FolderLockService? _folderLockService;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  final log = Logger('RecentPage');

  /// Mitigates a bug where files got imported starting with `null/` instead of `/`.
  ///
  /// This caused them to be written to `Documents/Sabernull/...` instead of `Documents/Saber/...`.
  ///
  /// See https://github.com/saber-notes/saber/issues/996
  /// and https://github.com/saber-notes/saber/pull/977.
  void moveIncorrectlyImportedFiles() async {
    for (final filePath in stows.recentFiles.value) {
      if (filePath.startsWith('/')) continue;

      final String newFilePath;
      if (filePath.startsWith('null/')) {
        newFilePath = await FileManager.suffixFilePathToMakeItUnique(
          filePath.substring('null'.length),
        );
      } else {
        newFilePath = await FileManager.suffixFilePathToMakeItUnique(
          '/$filePath',
        );
      }

      log.warning(
        'Found incorrectly imported file at `$filePath`; moving to `$newFilePath`',
      );
      await FileManager.moveFile(filePath, newFilePath);
    }
  }

  @override
  void initState() {
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_setState);

    super.initState();
    moveIncorrectlyImportedFiles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the scope means an unlock, a lock or leaving the app
    // re-labels the list (PRD FR-20).
    _folderLockService = FolderLockScope.of(context);
    findRecentlyAccessedNotes();
  }

  @override
  void dispose() {
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    findRecentlyAccessedNotes(fromFileListener: true);
  }

  void _setState() => setState(() {});

  Future findRecentlyAccessedNotes({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      // don't refresh if we're not on the home page
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
    }

    final check = ++_visibilityCheck;
    final children = await FileManager.getRecentlyAccessed();
    final hidden = await _hiddenNotes(children);
    if (!mounted || check != _visibilityCheck) return;

    filePaths
      ..clear()
      ..addAll(children);
    hiddenFiles = hidden;
    failed = children.isEmpty;

    setState(() {});
  }

  /// Labels the notes whose folder is locked and closed right now.
  ///
  /// The list itself is never filtered: order and selection stay, and a hidden
  /// note still shows its title and lock mark (PRD FR-20).
  Future<Set<String>> _hiddenNotes(List<String> paths) async {
    final service = _folderLockService;
    if (service == null) return {};

    final open = <String, bool>{
      for (final path in paths) path: await service.isOpen(path),
    };
    return RecentNoteVisibility.hiddenNotes(
      paths,
      isOpen: (path) => open[path] ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final crossAxisCount = MediaQuery.sizeOf(context).width ~/ 300 + 1;
    useListenable(stows.homeLayout);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const .only(bottom: 8),
            sliver: SliverAppBar(
              collapsedHeight: kToolbarHeight,
              expandedHeight: platform.isMaterialNative ? 200 : null,
              pinned: true,
              scrolledUnderElevation: 1,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  t.home.titles.home,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  bottom: 16,
                ),
              ),
              actions: const [HomeLayoutButton(), SyncingButton()],
            ),
          ),
          if (failed) ...[
            const SliverSafeArea(sliver: SliverToBoxAdapter(child: Welcome())),
          ] else ...[
            SliverSafeArea(
              minimum: const .only(
                // Allow space for the FloatingActionButton
                bottom: 70,
              ),
              sliver: MasonryFiles(
                crossAxisCount: crossAxisCount,
                files: [for (final filePath in filePaths) filePath],
                selectedFiles: selectedFiles,
                lockedFiles: hiddenFiles,
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: NewNoteButton(cupertino: platform.isCupertino),
      persistentFooterButtons: selectedFiles.value.isEmpty
          ? null
          : [
              Collapsible(
                axis: .vertical,
                collapsed: selectedFiles.value.length != 1,
                child: RenameNoteButton(
                  existingPath: selectedFiles.value.isEmpty
                      ? ''
                      : selectedFiles.value.first,
                  unselectNotes: () => selectedFiles.value = [],
                ),
              ),
              MoveNoteButton(
                filesToMove: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              DeleteNoteButton(
                filesToDelete: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              ExportNoteButton(selectedFiles: selectedFiles.value),
            ],
    );
  }
}
