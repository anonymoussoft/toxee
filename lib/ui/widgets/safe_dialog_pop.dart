import 'package:flutter/widgets.dart';

/// Pop the route that owns [context] with [result], but ONLY while that route is
/// still the topmost (current) one.
///
/// A dialog button's `onPressed` can fire TWICE in quick succession — a real
/// fast double-click, or a test harness (flutter_skill) that dispatches a
/// synthetic pointer AND directly invokes `onPressed`. An unguarded
/// `Navigator.pop` then runs twice: the first closes the dialog, the second —
/// invoked while the button is still mounted mid-dismiss — unwinds the PAGE
/// underneath (e.g. the root HomePage), emptying the Navigator and blanking the
/// whole window. `ModalRoute.isCurrent` flips to false synchronously inside the
/// first `Navigator.pop`, so the guarded second call is a no-op.
///
/// Single-tap behaviour is unchanged: the first call pops normally. This is the
/// shared form of the inline guard in `home_page.dart`'s
/// `buildDeleteConversationDialog`; use it for every dialog button that pops a
/// route, especially dialogs shown directly over a root page (where the stray
/// second pop has nothing left to land on).
void popDialogIfCurrent<T>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route != null && route.isCurrent) {
    Navigator.of(context).pop(result);
  }
}
