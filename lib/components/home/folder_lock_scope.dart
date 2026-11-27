import 'package:flutter/widgets.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

/// Hands the [FolderLockService] to the widget tree, and rebuilds whatever
/// depends on it when a lock appears or disappears (PRD FR-6).
class FolderLockScope extends InheritedNotifier<FolderLockService> {
  const new({
    super.key,
    required FolderLockService service,
    required super.child,
  }) : super(notifier: service);

  /// The nearest service above [context], or null when there is none.
  static FolderLockService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FolderLockScope>()?.notifier;

  /// Runs [action] — a share sheet, a file picker or a permission prompt —
  /// without treating the system UI covering the app as leaving (FR-28,
  /// DEC-21). Without a scope the action simply runs.
  static Future<T> runSystemFlow<T>(
    BuildContext context,
    Future<T> Function() action,
  ) {
    final service = maybeOf(context);
    return service == null ? action() : service.runDuringSystemFlow(action);
  }

  /// The nearest service above [context].
  static FolderLockService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FolderLockScope>();
    assert(
      scope?.notifier != null,
      'No FolderLockScope found above this widget',
    );
    return scope!.notifier!;
  }
}
