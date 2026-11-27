import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// A locked note tells the person its title and nothing else (PRD FR-20,
/// FR-21): no preview, not even one left on disk from before the lock.
void main() {
  const folder = '/preview_lock_test';
  const notePath = '$folder/secret';
  const thumbPath = '$notePath.sbn2.p';
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
      thumbPath,
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      ),
      awaitWrite: true,
    );
    stows.recentFiles.value = [];

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

  Widget card({required bool isLocked}) => FolderLockScope(
    service: service,
    child: MaterialApp(
      home: Scaffold(
        body: PreviewCard(
          filePath: notePath,
          toggleSelection: (_, _) {},
          selected: false,
          isAnythingSelected: false,
          isLocked: isLocked,
        ),
      ),
    ),
  );

  testWidgets('a locked note shows its title and mark, never the stale preview', (
    tester,
  ) async {
    await tester.pumpWidget(card(isLocked: true));
    await tester.pumpAndSettle();

    expect(find.text('secret'), findsOneWidget);
    expect(find.byTooltip('Locked'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(
      find.byType(Image),
      findsNothing,
      reason: 'a preview that predates the lock must not be displayed',
    );
  });

  testWidgets('the same note without a lock shows its preview', (
    tester,
  ) async {
    await tester.pumpWidget(card(isLocked: false));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
  });

  testWidgets('unlocking turns the card back into a preview', (tester) async {
    await tester.pumpWidget(card(isLocked: true));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(card(isLocked: false));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byTooltip('Locked'), findsNothing);
  });

  testWidgets('tapping a locked note asks for the password', (tester) async {
    await tester.pumpWidget(card(isLocked: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('secret'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
