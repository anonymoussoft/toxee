import 'package:flutter/widgets.dart';

import 'home_page_controller.dart';

/// Provides [HomePageController] to descendants.
class HomePageScope extends InheritedWidget {
  const HomePageScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final HomePageController controller;

  static HomePageController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HomePageScope>();
    assert(scope != null, 'No HomePageScope found in context');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(HomePageScope oldWidget) =>
      controller != oldWidget.controller;
}
