import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
  });

  test('L3 export save override short-circuits native picker', () async {
    debugSetL3TestSurfaceEnabledForTests(true);
    debugSetExportSaveFileOverridePathForTests('/tmp/l3-export.tox');

    var nativePickerCalls = 0;
    final resolvedPath = await runL3AwareExportSaveFilePicker(
      dialogTitle: 'Export Account',
      fileName: 'seeded_8895A8D6.tox',
      saveFile: (dialogTitle, fileName) async {
        nativePickerCalls += 1;
        return '/tmp/native-picker.tox';
      },
    );

    expect(resolvedPath, '/tmp/l3-export.tox');
    expect(nativePickerCalls, 0);
  });

  test('normal path still invokes native save picker', () async {
    debugSetL3TestSurfaceEnabledForTests(false);
    debugSetExportSaveFileOverridePathForTests('/tmp/l3-export.tox');

    var nativePickerCalls = 0;
    String? seenDialogTitle;
    String? seenFileName;
    final resolvedPath = await runL3AwareExportSaveFilePicker(
      dialogTitle: 'Export Account',
      fileName: 'seeded_8895A8D6.tox',
      saveFile: (dialogTitle, fileName) async {
        nativePickerCalls += 1;
        seenDialogTitle = dialogTitle;
        seenFileName = fileName;
        return '/tmp/native-picker.tox';
      },
    );

    expect(resolvedPath, '/tmp/native-picker.tox');
    expect(nativePickerCalls, 1);
    expect(seenDialogTitle, 'Export Account');
    expect(seenFileName, 'seeded_8895A8D6.tox');
  });
}
