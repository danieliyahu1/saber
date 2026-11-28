import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_lifecycle.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/note_unlock_gate.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// PRD FR-28 and FR-29 end to end: unlock, put the app away (background,
/// screen lock or closed window all arrive as the same lifecycle states), and
/// return to a locked folder — with or without a note open.
void main() {
  const folderName = 'session_end_flow_test';
  const folder = '/$folderName';
  const notePath = '$folder/entry';
  const password = 'hunter2';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    stows.sentryConsent.value = .granted;
    await FileManager.deleteDirectory(folder);
    await FileManager.createFolder(folder);
    await FileManager.writeFile('$notePath.sbn2', [1], awaitWrite: true);
    stows.recentFiles.value = [];

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
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  Future<void> putAway(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pumpAndSettle();
  }

  Widget app() => FolderLockScope(
    service: service,
    // ignore: prefer_const_constructors - MaterialApp is not const
    child: FolderLockLifecycle(
      child: const MaterialApp(home: BrowsePage(path: folder)),
    ),
  );

  testWidgets('unlock, background, return — the folder is locked again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('entry'), findsOneWidget);

    // A screen lock and a switch to another app are both paused, so this one
    // case covers both.
    await putAway(tester, AppLifecycleState.paused);
    expect(await service.isOpen(folder), isFalse);

    await putAway(tester, AppLifecycleState.resumed);

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('entry'), findsNothing);
  });

  testWidgets('unlock, hide the app, return — still locked', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    await putAway(tester, AppLifecycleState.hidden);
    await putAway(tester, AppLifecycleState.resumed);

    expect(find.text('This folder is locked.'), findsOneWidget);
  });

  testWidgets('a note open at session end comes back as its locked folder', (
    tester,
  ) async {
    await tester.pumpWidget(
      FolderLockScope(
        service: service,
        child: FolderLockLifecycle(
          child: MaterialApp(
            home: NoteUnlockGate(
              notePath: notePath,
              builder: (context) => const Text('editor'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);

    await putAway(tester, AppLifecycleState.paused);
    await putAway(tester, AppLifecycleState.resumed);

    expect(find.text('editor'), findsNothing);
    expect(find.text('This folder is locked.'), findsOneWidget);
  });
}
