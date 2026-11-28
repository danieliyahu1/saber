import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/delete_folder_button.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/note_unlock_gate.dart';
import 'package:saber/components/home/rename_folder_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// Regression cover for PRD FR-27: inside an unlocked folder the library
/// actions are the ordinary ones — no password, no lock screen, no extra step.
///
/// These widgets take no lock service at all, which is the point: the gate
/// lives in front of folder contents and note openings, never in front of the
/// actions that keep a locked folder a normal folder.
void main() {
  const folder = '/unlocked_actions_test';
  const notePath = '$folder/entry.sbn2';

  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    stows.sentryConsent.value = .granted;
    await FileManager.createFolder(folder);
    await FileManager.writeFile(notePath, [1], awaitWrite: true);
    service = FolderLockService(
      repository: MemoryFolderLockRepository(),
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() async {
    service.dispose();
    await FileManager.deleteDirectory(folder);
  });

  testWidgets('renaming an unlocked folder opens the usual dialog', (
    tester,
  ) async {
    String? renamedTo;
    await tester.pumpWidget(
      _app(
        RenameFolderButton(
          folderName: 'unlocked_actions_test',
          doesFolderExist: (_) => false,
          renameFolder: (newName) async => renamedTo = newName,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pumpAndSettle();

    expect(find.text('Rename folder'), findsOneWidget);
    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Wrong password.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'renamed_folder');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renamedTo, 'renamed_folder');
  });

  testWidgets('deleting an unlocked folder asks only the usual confirmation', (
    tester,
  ) async {
    String? deleted;
    await tester.pumpWidget(
      _app(
        DeleteFolderButton(
          folderName: 'unlocked_actions_test',
          deleteFolder: (folderName) async => deleted = folderName,
          isFolderEmpty: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();

    expect(find.textContaining('unlocked_actions_test'), findsWidgets);
    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.byType(TextField), findsNothing, reason: 'no password field');

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, 'unlocked_actions_test');
  });

  testWidgets('a non-empty locked folder asks the ordinary extra question', (
    tester,
  ) async {
    await service.lock(folder, 'hunter2');
    await service.unlock(folder, 'hunter2');
    String? deleted;

    await tester.pumpWidget(
      FolderLockScope(
        service: service,
        child: MaterialApp(
          home: Scaffold(
            body: DeleteFolderButton(
              folderName: 'unlocked_actions_test',
              deleteFolder: (folderName) async => deleted = folderName,
              isFolderEmpty: (_) async => false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Wrong password.'), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, 'unlocked_actions_test');
  });

  testWidgets('moving a note out of an unlocked folder asks no password', (
    tester,
  ) async {
    await service.lock(folder, 'hunter2');
    await service.unlock(folder, 'hunter2');

    await tester.pumpWidget(
      FolderLockScope(
        service: service,
        child: MaterialApp(
          home: Scaffold(
            body: MoveNoteButton(
              filesToMove: const [notePath],
              unselectNotes: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.drive_file_move));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Wrong password.'), findsNothing);
    expect(find.textContaining('entry.sbn2'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('a new note in an unlocked folder opens without a prompt', (
    tester,
  ) async {
    await service.lock(folder, 'hunter2');
    await service.unlock(folder, 'hunter2');
    var editorBuilds = 0;

    await tester.pumpWidget(
      FolderLockScope(
        service: service,
        child: MaterialApp(
          home: NoteUnlockGate(
            notePath: '$folder/untitled.sbn2',
            builder: (context) {
              editorBuilds++;
              return const Text('fresh editor');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('fresh editor'), findsOneWidget);
    expect(editorBuilds, 1);
  });
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));
