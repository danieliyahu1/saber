import 'package:flutter/widgets.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

/// Closes every unlocked folder when the app is put away (PRD FR-28).
///
/// Only [AppLifecycleState.paused], [AppLifecycleState.hidden] and
/// [AppLifecycleState.detached] count as leaving the app: the last one is a
/// desktop window closing. [AppLifecycleState.inactive] is the notification
/// shade, a system dialog, the share sheet or the file picker, and must not
/// clear the session (PRD FR-28, DEC-21).
class FolderLockLifecycle extends StatefulWidget {
  const new({super.key, required this.child});

  final Widget child;

  @override
  State<FolderLockLifecycle> createState() => _FolderLockLifecycleState();
}

class _FolderLockLifecycleState extends State<FolderLockLifecycle>
    with WidgetsBindingObserver {
  /// Resolved from [FolderLockScope] so every gate shares one session set.
  FolderLockService? _service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = FolderLockScope.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _service?.relockAll();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
