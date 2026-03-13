import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  group('Prefs.clearAccountData', () {
    test('removes only target account scoped keys', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'current_account_tox_id': 'toxA',
        'friend_nickname_alice_toxA': 'Alice A',
        'friend_nickname_alice_toxB': 'Alice B',
        'account_password_salt_toxA': 'saltA',
        'account_password_salt_toxB': 'saltB',
      });

      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      await Prefs.clearAccountData('toxA');

      expect(prefs.getString('friend_nickname_alice_toxA'), isNull);
      expect(prefs.getString('friend_nickname_alice_toxB'), 'Alice B');
      expect(prefs.getString('account_password_salt_toxB'), 'saltB');
    });
  });

  group('Prefs.getUniqueAccountByNickname', () {
    test('returns single account when unique', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'account_list': jsonEncode([
          {'toxId': 'id1', 'nickname': 'Alice', 'statusMessage': ''},
        ]),
      });

      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      final account = await Prefs.getUniqueAccountByNickname('Alice');

      expect(account, isNotNull);
      expect(account!['toxId'], 'id1');
      expect(account['nickname'], 'Alice');
    });

    test('returns null when no match', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'account_list': jsonEncode([
          {'toxId': 'id1', 'nickname': 'Bob', 'statusMessage': ''},
        ]),
      });

      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      final account = await Prefs.getUniqueAccountByNickname('Alice');

      expect(account, isNull);
    });

    test('throws StateError when duplicate nickname', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'account_list': jsonEncode([
          {'toxId': 'id1', 'nickname': 'Alice', 'statusMessage': ''},
          {'toxId': 'id2', 'nickname': 'Alice', 'statusMessage': ''},
        ]),
      });

      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);

      expect(
        () => Prefs.getUniqueAccountByNickname('Alice'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
