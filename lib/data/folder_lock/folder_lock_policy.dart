/// Path rules for locked folders.
///
/// Everything here is pure: no files, no widgets, no service. The questions
/// "is this path inside that one?" and "which locked folder covers this path?"
/// are the ones every gate asks, so they are answered in one place (HLD §6).
abstract final class FolderLockPolicy {
  /// [path] in the spelling the rest of the feature uses: forward slashes, one
  /// leading slash, and no trailing slash except for the root.
  ///
  /// Windows separators are accepted because a path can reach the app from the
  /// platform; nothing else about the path is reinterpreted.
  static String normalise(String path) {
    var normalised = path.replaceAll('\\', '/');
    while (normalised.contains('//')) {
      normalised = normalised.replaceAll('//', '/');
    }
    if (!normalised.startsWith('/')) normalised = '/$normalised';
    if (normalised.length > 1 && normalised.endsWith('/')) {
      normalised = normalised.substring(0, normalised.length - 1);
    }
    return normalised;
  }

  /// Whether [path] is [ancestor] itself or lives beneath it.
  ///
  /// `/A` does not contain `/AB`: only a whole path segment counts, so a
  /// prefix alone is never enough.
  static bool isInside(String ancestor, String path) {
    final parent = normalise(ancestor);
    final child = normalise(path);
    if (parent == '/') return true;
    return child == parent || child.startsWith('$parent/');
  }

  /// [path] and every folder above it, closest first, ending at the root.
  ///
  /// A locked folder covers itself, so [path] comes first.
  static List<String> ancestorsOf(String path) {
    final normalised = normalise(path);
    if (normalised == '/') return const ['/'];

    final segments = normalised.substring(1).split('/');
    return [
      for (var depth = segments.length; depth > 0; depth--)
        '/${segments.take(depth).join('/')}',
      '/',
    ];
  }

  /// The closest folder at or above [path] that [isLocked] says is locked.
  ///
  /// The nearest lock wins, so a locked folder inside another locked folder is
  /// asked about separately (PRD FR-15). Returns null when nothing covers
  /// [path].
  static Future<String?> nearestLockedAncestor(
    String path,
    Future<bool> Function(String folder) isLocked,
  ) async {
    for (final candidate in ancestorsOf(path)) {
      if (await isLocked(candidate)) return candidate;
    }
    return null;
  }
}
