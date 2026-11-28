import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_lifecycle.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

/// PRD FR-28: the app locks every unlocked folder when it is put away, and
/// only then — a share sheet or a system prompt is not leaving the app
/// (DEC-21).
void main() {
  const folder = '/notes';
  const password = 'hunter2';

  late FolderLockService service;

  setUp(() async {
    final repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
    await service.unlock(folder, password);
  });

  tearDown(() {
    service.dispose();
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    FolderLockScope(
      service: service,
      child: const FolderLockLifecycle(child: MaterialApp(home: SizedBox())),
    ),
  );

  Future<void> putAppAway(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  testWidgets('paused closes every unlocked folder (FR-28)', (tester) async {
    await pumpApp(tester);
    expect(await service.isOpen(folder), isTrue);

    await putAppAway(tester, AppLifecycleState.paused);

    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('hidden closes every unlocked folder', (tester) async {
    await pumpApp(tester);

    await putAppAway(tester, AppLifecycleState.hidden);

    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('a closing desktop window counts', (tester) async {
    await pumpApp(tester);

    await putAppAway(tester, AppLifecycleState.detached);

    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('inactive is a share sheet, not leaving the app (DEC-21)', (
    tester,
  ) async {
    await pumpApp(tester);

    await putAppAway(tester, AppLifecycleState.inactive);

    expect(await service.isOpen(folder), isTrue);
  });

  testWidgets('two rapid pauses clear the session once', (tester) async {
    await pumpApp(tester);
    var notifications = 0;
    service.addListener(() => notifications++);

    await putAppAway(tester, AppLifecycleState.paused);
    await putAppAway(tester, AppLifecycleState.paused);

    expect(notifications, 1);
    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('resuming keeps the folder locked (FR-28)', (tester) async {
    await pumpApp(tester);
    await putAppAway(tester, AppLifecycleState.paused);

    await putAppAway(tester, AppLifecycleState.resumed);

    expect(await service.isOpen(folder), isFalse);
  });
}
