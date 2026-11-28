import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/unlock_folder_screen.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';

void main() {
  const folder = '/notes';
  const password = 'hunter2';

  late _MemoryRepository repository;
  late FolderLockService service;

  setUp(() {
    repository = _MemoryRepository();
    service = FolderLockService(repository: repository, hasher: _EchoHasher());
    repository.locks[folder] = _lockFor(password);
  });

  tearDown(() => service.dispose());

  Widget app({ValueChanged<String>? onUnlocked}) => MaterialApp(
    home: Scaffold(
      body: FolderLockScope(
        service: service,
        child: UnlockFolderScreen(
          folderPath: folder,
          onUnlocked: onUnlocked ?? (_) {},
        ),
      ),
    ),
  );

  testWidgets('shows the PRD copy and starts in the password field', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Show password'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue, reason: 'NFR-9');
  });

  testWidgets('a wrong password says so, then the right one opens the folder', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(app(onUnlocked: (folder) => opened = folder));

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong password.'), findsOneWidget);
    expect(opened, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
      reason: 'the person may try again at once (FR-19)',
    );

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(opened, folder);
  });

  testWidgets('the wrong-password message is readable by a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.text('Wrong password.'));
    expect(node.label, contains('Wrong password.'));

    semantics.dispose();
  });

  testWidgets('an empty submit never reaches the service', (tester) async {
    await tester.pumpWidget(app());

    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(repository.existsCalls, 0);
    expect(find.text('Wrong password.'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('one check runs at a time', (tester) async {
    String? opened;
    await tester.pumpWidget(app(onUnlocked: (folder) => opened = folder));
    await tester.enterText(find.byType(TextField), password);

    repository.gate = Completer();
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'the button is disabled while the password is being checked',
    );

    await tester.tap(find.text('Unlock'), warnIfMissed: false);
    await tester.pump();

    repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(repository.reads, 1);
    expect(opened, folder);
  });

  testWidgets('show password reveals only while toggled', (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), password);

    EditableText editable() =>
        tester.widget<EditableText>(find.byType(EditableText));

    expect(editable().obscureText, isTrue);

    await tester.tap(find.text('Show password'));
    await tester.pump();
    expect(editable().obscureText, isFalse);

    await tester.tap(find.text('Show password'));
    await tester.pump();
    expect(editable().obscureText, isTrue);
  });

  testWidgets('cancel returns to the previous view without unlocking', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: FolderLockScope(
                        service: service,
                        child: UnlockFolderScreen(
                          folderPath: folder,
                          onUnlocked: (_) => opened = true,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open folder'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open folder'));
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('open folder'), findsOneWidget);
    expect(opened, isFalse);
  });
}

FolderLock _lockFor(String password) {
  final hasher = _EchoHasher();
  final salt = hasher.createSalt();
  return FolderLock(
    salt: salt,
    iterations: hasher.iterations,
    hash: hasher.derive(password, salt: salt, iterations: hasher.iterations),
  );
}

/// A hasher that maps a password to recognisable bytes; PBKDF2 has its own
/// tests, and the screen is not the place to re-run them.
final class _EchoHasher implements PasswordHasher {
  static const _salt = [1, 2, 3, 4];

  @override
  int get iterations => 2;

  @override
  Uint8List createSalt() => Uint8List.fromList(_salt);

  @override
  Uint8List derive(
    String password, {
    required Uint8List salt,
    required int iterations,
  }) => Uint8List.fromList(
    utf8.encode('$iterations:$password:${base64Encode(salt)}'),
  );

  @override
  bool matches(
    String password, {
    required Uint8List salt,
    required int iterations,
    required Uint8List expectedHash,
  }) {
    final actual = derive(password, salt: salt, iterations: iterations);
    if (actual.length != expectedHash.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expectedHash[i]) return false;
    }
    return true;
  }
}

final class _MemoryRepository implements FolderLockRepository {
  final locks = <String, FolderLock>{};

  /// When set, `exists` waits for it, holding a check in flight.
  Completer<void>? gate;

  var existsCalls = 0;
  var reads = 0;

  @override
  Future<bool> exists(String folderPath) async {
    existsCalls++;
    if (gate case final pending?) await pending.future;
    return locks.containsKey(folderPath);
  }

  @override
  Future<FolderLockRead?> read(String folderPath) async {
    reads++;
    final lock = locks[folderPath];
    return lock == null ? null : FolderLockFound(lock);
  }

  @override
  Future<FolderLockWriteResult> write(
    String folderPath,
    FolderLock lock,
  ) async {
    locks[folderPath] = lock;
    return const FolderLockWritten();
  }

  @override
  Future<bool> delete(String folderPath) async {
    locks.remove(folderPath);
    return true;
  }
}
