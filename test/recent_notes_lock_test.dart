import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/home/recent_notes.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// Home may list a locked note, but only as a title and a lock mark — and the
/// preview must not exist in the widget tree (PRD FR-20, FR-21).
void main() {
  const folder = '/recent_notes_lock_test';
  const notePath = '$folder/secret';
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
    await FileManager.writeFile('$notePath.sbn2', [1], awaitWrite: true);
    await FileManager.writeFile(
      '$notePath.sbn2.p',
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      ),
      awaitWrite: true,
    );
    stows.recentFiles.value = ['$notePath.sbn2'];

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
    stows.recentFiles.value = [];
  });

  Widget app() => FolderLockScope(
    service: service,
    child: const MaterialApp(home: RecentPage()),
  );

  testWidgets('a locked recent note shows title and mark, not a preview', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('secret'), findsOneWidget);
    expect(find.byTooltip('Locked'), findsOneWidget);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'the preview must not be in the widget tree at all',
    );
  });

  testWidgets('unlocking the folder turns the entry back into a preview', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);

    await service.unlock(folder, password);
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byTooltip('Locked'), findsNothing);
  });

  testWidgets('tapping the locked title asks for the password', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('secret'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
