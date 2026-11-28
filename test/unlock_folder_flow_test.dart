import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/note_unlock_gate.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// The path a person actually walks once a folder is locked: reopen it, get
/// the password wrong once, get it right, open a note from inside the folder,
/// then come back through Home's recent notes.
///
/// The lock record lives in memory so the asynchronous repository read can
/// complete on the test clock; the record itself is covered by
/// `file_folder_lock_repository_test`.
void main() {
  const folderName = 'unlock_flow_test';
  const folder = '/$folderName';
  const notePath = '$folder/entry.sbn2';
  const password = 'hunter2';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    await FileManager.deleteDirectory(folder);
    await FileManager.createFolder(folder);
    await FileManager.writeFile(notePath, [1], awaitWrite: true);
    stows.recentFiles.value = [notePath];
    stows.sentryConsent.value = .granted;

    BrowsePage.overrideChildren = DirectoryChildren(const [], const ['entry']);

    repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() async {
    service.dispose();
    BrowsePage.overrideChildren = null;
    await FileManager.deleteDirectory(folder);
    stows.recentFiles.value = [];
  });

  testWidgets('leave, reopen, unlock, then open a note from Home recents', (
    tester,
  ) async {
    // The folder was locked and the app was put away.
    expect(await service.isLocked(folder), isTrue);
    service.relockAll();

    // Reopening it asks for the password instead of showing the note.
    await tester.pumpWidget(_browseApp(service));
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('entry'), findsNothing);

    // A wrong password changes nothing.
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(find.text('entry'), findsNothing);
    expect(await service.isOpen(folder), isFalse);

    // The right password shows the folder in place.
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('entry'), findsOneWidget);
    expect(await service.isOpen(folder), isTrue);

    // From inside the folder a note opens without a second prompt.
    var editorBuilds = 0;
    await tester.pumpWidget(
      _gateApp(service, notePath, onEditorBuilt: () => editorBuilds++),
    );
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsNothing);
    expect(editorBuilds, 1);

    // Leaving again closes it, so Home's recent note must ask.
    service.relockAll();
    await tester.pumpWidget(_recentsApp(service, notePath));
    await tester.pumpAndSettle();
    await tester.tap(find.text('entry.sbn2'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.byType(Editor), findsNothing);

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(find.byType(Editor), findsNothing);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.byType(Editor), findsOneWidget);
    expect(await service.isOpen(folder), isTrue);
  });
}

Widget _browseApp(FolderLockService service) => MaterialApp(
  home: FolderLockScope(
    service: service,
    child: const BrowsePage(path: '/unlock_flow_test'),
  ),
);

/// The wrapper [PreviewCard.openBuilder] puts in front of the editor, with a
/// marker instead of the editor itself.
Widget _gateApp(
  FolderLockService service,
  String notePath, {
  required VoidCallback onEditorBuilt,
}) => FolderLockScope(
  service: service,
  child: MaterialApp(
    home: NoteUnlockGate(
      notePath: notePath,
      builder: (context) {
        onEditorBuilt();
        return Text('editor for $notePath');
      },
    ),
  ),
);

/// The recent-note card from Home, which opens the note through the same gate.
Widget _recentsApp(FolderLockService service, String notePath) =>
    FolderLockScope(
      service: service,
      child: MaterialApp(
        home: Scaffold(
          body: PreviewCard(
            filePath: notePath,
            selected: false,
            isAnythingSelected: false,
            toggleSelection: (_, _) {},
          ),
        ),
      ),
    );
