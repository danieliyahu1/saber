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
