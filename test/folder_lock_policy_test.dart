import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/folder_lock/folder_lock_policy.dart';

void main() {
  group('FolderLockPolicy.normalise', () {
    test('leaves a plain path alone', () {
      expect(FolderLockPolicy.normalise('/A/B'), '/A/B');
    });

    test('drops a trailing slash', () {
      expect(FolderLockPolicy.normalise('/A/B/'), '/A/B');
    });

    test('accepts Windows separators', () {
      expect(FolderLockPolicy.normalise(r'\A\B'), '/A/B');
    });

    test('adds the leading slash', () {
      expect(FolderLockPolicy.normalise('A/B'), '/A/B');
    });

    test('collapses repeated slashes', () {
      expect(FolderLockPolicy.normalise('/A//B'), '/A/B');
    });

    test('keeps the root', () {
      expect(FolderLockPolicy.normalise('/'), '/');
    });
  });

  group('FolderLockPolicy.isInside', () {
    test('a folder contains itself', () {
      expect(FolderLockPolicy.isInside('/A', '/A'), isTrue);
    });

    test('a folder contains its descendants', () {
      expect(FolderLockPolicy.isInside('/A', '/A/B/C'), isTrue);
    });

    test('/A does not contain /AB', () {
      expect(FolderLockPolicy.isInside('/A', '/AB'), isFalse);
      expect(FolderLockPolicy.isInside('/AB', '/A'), isFalse);
    });

    test('a child does not contain its parent', () {
      expect(FolderLockPolicy.isInside('/A/B', '/A'), isFalse);
    });

    test('the root contains everything', () {
      expect(FolderLockPolicy.isInside('/', '/'), isTrue);
      expect(FolderLockPolicy.isInside('/', '/A/B'), isTrue);
    });

    test('normalises both sides', () {
      expect(FolderLockPolicy.isInside(r'\A', '/A/B/'), isTrue);
    });
  });

  group('FolderLockPolicy.ancestorsOf', () {
    test('lists the path first, the root last', () {
      expect(FolderLockPolicy.ancestorsOf('/A/B'), ['/A/B', '/A', '/']);
    });

    test('the root is its own only ancestor', () {
      expect(FolderLockPolicy.ancestorsOf('/'), ['/']);
    });

    test('normalises before walking', () {
      expect(FolderLockPolicy.ancestorsOf(r'\A\B\'), ['/A/B', '/A', '/']);
    });
  });

  group('FolderLockPolicy.nearestLockedAncestor', () {
    Future<String?> nearest(String path, Set<String> locked) =>
        FolderLockPolicy.nearestLockedAncestor(
          path,
          (folder) async => locked.contains(folder),
        );

    test('a locked path is its own nearest lock', () async {
      expect(await nearest('/A', {'/A'}), '/A');
    });

    test('the closest locked parent wins', () async {
      expect(await nearest('/A/B/C/note.sbn2', {'/A', '/A/B'}), '/A/B');
    });

    test('three locked ancestors: the closest still wins', () async {
      expect(
        await nearest('/A/B/C/note.sbn2', {'/A', '/A/B', '/A/B/C'}),
        '/A/B/C',
      );
    });

    test('nothing locked is null', () async {
      expect(await nearest('/A/B', {}), isNull);
    });

    test('normalises the path before walking', () async {
      expect(await nearest(r'\A\B\note', {'/A'}), '/A');
    });
  });
}
