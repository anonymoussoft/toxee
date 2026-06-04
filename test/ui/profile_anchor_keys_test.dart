library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/profile/profile_edit_fields.dart';
import 'package:toxee/ui/profile/profile_qr_section.dart';
import 'package:toxee/ui/settings/sidebar.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';
import 'package:path/path.dart' as p;

const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

class _SidebarHarnessService extends FfiChatService {
  _SidebarHarnessService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'profile_anchor_keys_test_',
    );
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
          return tempRoot.path;
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return p.join(tempRoot.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(tempRoot.path, 'temp');
        case 'getDownloadsDirectory':
          return p.join(tempRoot.path, 'Downloads');
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('Anchor Nick');
    await Prefs.setStatusMessage('Anchor Status');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  testWidgets('sidebar avatar opens profile with stable anchors', (
    WidgetTester tester,
  ) async {
    final service = _SidebarHarnessService();
    addTearDown(service.disposeStub);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => buildSidebar(
            context: context,
            selectedIndex: 0,
            onTap: (_) {},
            service: service,
            connectionStatusStream: service.connectionStatusStream,
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byKey(UiKeys.sidebarUserAvatar), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.sidebarUserAvatar));
    await _settle(tester);

    expect(find.byKey(UiKeys.profileToxIdCopyButton), findsOneWidget);
    expect(find.byKey(UiKeys.profileToxIdSelectableText), findsOneWidget);
  });

  testWidgets('profile tox id section exposes stable copy and text keys', (
    WidgetTester tester,
  ) async {
    var copyTapCount = 0;

    await tester.pumpWidget(
      _app(
        ProfileToxIdSection(
          userId: _toxId,
          label: 'User ID',
          copyLabel: 'Copy',
          primaryColor: Colors.blue,
          secondaryTextColor: Colors.grey,
          primaryTextColor: Colors.black,
          onCopy: () => copyTapCount += 1,
        ),
      ),
    );

    expect(find.byKey(UiKeys.profileToxIdCopyButton), findsOneWidget);
    expect(find.byKey(UiKeys.profileToxIdSelectableText), findsOneWidget);

    final selectable = tester.widget<SelectableText>(
      find.byKey(UiKeys.profileToxIdSelectableText),
    );
    expect(selectable.data, _toxId);

    await tester.tap(find.byKey(UiKeys.profileToxIdCopyButton));
    await tester.pump();
    expect(copyTapCount, 1);
  });

  testWidgets('profile qr section exposes stable copy key when enabled', (
    WidgetTester tester,
  ) async {
    const qrPath = '/tmp/profile_anchor_keys_qr.png';
    String? copiedPath;
    await tester.pumpWidget(
      _app(
        ProfileQrSection(
          qrFuture: Future<String>.value(qrPath),
          versionKey: 'test',
          isWide: true,
          primaryColor: Colors.blue,
          onSave: () {},
          onCopy: (path) => copiedPath = path,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(UiKeys.profileQrCopyButton), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.profileQrCopyButton));
    await tester.pump();
    expect(copiedPath, qrPath);
  });
}
