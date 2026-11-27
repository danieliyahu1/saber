import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_lifecycle.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

/// PRD FR-28 / DEC-21: a share sheet, a file picker or a permission prompt is
/// not leaving the app; a real background still locks (even if it starts while
/// one of those flows is open).
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

  /// Drives the binding, then lets the service's flow bookkeeping settle.
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  testWidgets('a share sheet covering the app does not clear the session', (
    tester,
  ) async {
    await pumpApp(tester);

    await service.runDuringSystemFlow(() async {
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.hidden);
      expect(await service.isOpen(folder), isTrue);
      await lifecycle(tester, AppLifecycleState.resumed);
    });

    expect(await service.isOpen(folder), isTrue);
  });

  testWidgets('export finishes and the folder is still open', (tester) async {
    await pumpApp(tester);

    await service.runDuringSystemFlow(() async {});

    expect(await service.isOpen(folder), isTrue);
  });

  testWidgets('a real background during a flow locks when the flow ends', (
    tester,
  ) async {
    await pumpApp(tester);

    await service.runDuringSystemFlow(() async {
      await lifecycle(tester, AppLifecycleState.paused);
      // Still inside the export/share flow: the pause is not counted yet.
      expect(await service.isOpen(folder), isTrue);
    });

    // The flow ended while the app was still in the background, so the
    // session is gone now (FR-28).
    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('a real background outside a flow still locks', (tester) async {
    await pumpApp(tester);

    await lifecycle(tester, AppLifecycleState.paused);

    expect(await service.isOpen(folder), isFalse);
  });

  testWidgets('a failed share does not change the lock state', (tester) async {
    await pumpApp(tester);

    await expectLater(
      service.runDuringSystemFlow<void>(
        () async => throw StateError('user cancelled'),
      ),
      throwsStateError,
    );

    expect(await service.isOpen(folder), isTrue);
    expect(service.isInSystemFlow, isFalse);
  });
}
