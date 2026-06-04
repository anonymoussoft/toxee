import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../ui/home_page.dart';
import '../ui/widgets/app_page_route.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<bool> navigateToHomeIfPossible(FfiChatService service) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return false;
  unawaited(
    navigator.pushReplacement(AppPageRoute(page: HomePage(service: service))),
  );
  return true;
}
