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
    final service = FolderLockScope.of(context);
    if (!identical(service, _service)) {
      _service = service;
      service.appIsForeground = _isForeground;
    }
  }

  @override
  void dispose() {
    _service?.appIsForeground = FolderLockService.defaultForegroundCheck;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The binding's word on whether the app is in front; null means the first
  /// frame, which counts as in front.
  bool _isForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_service?.isInSystemFlow ?? false) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _service?.relockAll();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
