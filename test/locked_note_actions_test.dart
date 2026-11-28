import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// A locked note must not leave its folder through a side door: exporting it
/// reads it, moving it takes it out, and the move picker must not list what is
/// inside a locked folder (PRD FR-10, FR-17, NFR-6).
void main() {
  const folder = '/locked_note_actions_test';
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
    stows.sentryConsent.value = .granted;
    await FileManager.createFolder(folder);
    await FileManager.writeFile(notePath, [1], awaitWrite: true);

    repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() async {
    service.dispose();
    await FileManager.deleteDirectory(folder);
  });

  Widget app(Widget child) => FolderLockScope(
    service: service,
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('exporting a locked note asks for the password first', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const ExportNoteButton(selectedFiles: [notePath])),
    );
    await tester.pump();

    // The speed dial rotates forever and its children are hard to hit in a
    // test, so the PDF action is invoked directly.
    final dial = tester.widget<SpeedDial>(find.byType(SpeedDial));
    final pdf = dial.children.firstWhere((child) => child.label == 'PDF');
    pdf.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('This folder is locked.'), findsNothing);
    expect(await service.isOpen(notePath), isFalse);
  });

  testWidgets('moving a locked note asks for the password before the picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(MoveNoteButton(filesToMove: const [notePath], unselectNotes: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.drive_file_move));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('Move'), findsNothing, reason: 'the picker is not open');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Move'), findsNothing);
  });

  testWidgets('the right password opens the note folder, then the picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(MoveNoteButton(filesToMove: const [notePath], unselectNotes: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.drive_file_move));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Move'), findsOneWidget);
  });

  group('the move picker', () {
    const pickerFolder = '/locked_picker_test';
    const sourceNote = '$pickerFolder/entry.sbn2';
    const vault = '$pickerFolder/vault';

    late MemoryFolderLockRepository pickerRepository;
    late FolderLockService pickerService;

    setUp(() async {
      stows.sentryConsent.value = .granted;
      await FileManager.createFolder(pickerFolder);
      await FileManager.writeFile(sourceNote, [1], awaitWrite: true);

      pickerRepository = MemoryFolderLockRepository();
      pickerRepository.locks[vault] = lockAccepting(password);
      pickerService = FolderLockService(
        repository: pickerRepository,
        hasher: EchoPasswordHasher(),
      );
    });

    tearDown(() async {
      pickerService.dispose();
      await FileManager.deleteDirectory(pickerFolder);
    });

    /// The picker's folder tree, handed in because real directory reads never
    /// finish inside the widget-test clock.
    Future<DirectoryChildren?> childrenOf(String folder) async {
      return switch (folder) {
        '$pickerFolder/' => DirectoryChildren(const ['vault'], const ['entry']),
        '$vault/' => DirectoryChildren(const ['inner', 'other'], const []),
        _ => null,
      };
    }

    testWidgets('asks for the password instead of listing a locked folder', (
      tester,
    ) async {
      await tester.pumpWidget(
        FolderLockScope(
          service: pickerService,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: MoveNoteButton(
                  filesToMove: const [sourceNote],
                  unselectNotes: () {},
                  childrenOf: childrenOf,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.drive_file_move));
      await tester.pumpAndSettle();

      expect(find.text('vault'), findsOneWidget);

      await tester.tap(find.text('vault'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsOneWidget);
      expect(find.text('inner'), findsNothing);
      expect(find.text('other'), findsNothing);

      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('inner'), findsOneWidget);
      expect(find.text('other'), findsOneWidget);
    });
  });
}
