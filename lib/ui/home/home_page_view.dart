import 'package:flutter/widgets.dart';

import 'home_page_scope.dart';

/// Placeholder view for HomePage content. Obtain [HomePageController] via
/// [HomePageScope.of](context). Real content remains in [HomePage] until
/// full migration.
class HomePageView extends StatelessWidget {
  const HomePageView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
