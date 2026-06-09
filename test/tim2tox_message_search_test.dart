// L1 gate for S93 — the in-conversation message search MATCHER, the pure core
// of the `Tim2ToxSdkPlatform.searchLocalMessages` fix (the C++
// `SearchLocalMessages` is an empty stub, so toxee's message search was
// returning nothing until this override searched the Dart-side history).
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/message_search.dart';

ChatMessage _msg(
  String text, {
  String? fileName,
  String? mediaKind,
  bool isSelf = false,
}) =>
    ChatMessage(
      text: text,
      fromUserId: isSelf ? 'self' : 'peer',
      isSelf: isSelf,
      timestamp: DateTime(2024, 1, 1),
      fileName: fileName,
      mediaKind: mediaKind,
      msgID: 'm',
    );

void main() {
  group('S93 chatMessageMatchesKeywords', () {
    test('case-insensitive substring on the bubble text', () {
      final m = _msg('Order a Pizza tonight');
      expect(chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
          isTrue);
      expect(chatMessageMatchesKeywords(m, keywords: ['PIZZA'], matchAll: false),
          isTrue,
          reason: 'match must be case-insensitive');
      expect(chatMessageMatchesKeywords(m, keywords: ['burger'], matchAll: false),
          isFalse);
    });

    test('OR matches ANY keyword; AND requires ALL', () {
      final m = _msg('pizza and salad');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'burger'], matchAll: false),
          isTrue,
          reason: 'OR: pizza present');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'burger'], matchAll: true),
          isFalse,
          reason: 'AND: burger absent');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'salad'], matchAll: true),
          isTrue,
          reason: 'AND: both present');
    });

    test('a file message matches by its fileName', () {
      final m = _msg('', fileName: 'quarterly-pizza-report.pdf', mediaKind: 'file');
      expect(chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
          isTrue,
          reason: 'owned payload fields include fileName, not just text');
    });

    test('control-signal messages are NEVER searchable', () {
      for (final prefix in kSearchControlSignalPrefixes) {
        final m = _msg('${prefix}pizza{"x":1}');
        expect(
            chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
            isFalse,
            reason: '$prefix messages must be excluded from search results');
      }
    });

    test('empty / whitespace keywords are ignored; no effective keyword matches '
        'nothing', () {
      final m = _msg('pizza');
      expect(chatMessageMatchesKeywords(m, keywords: [], matchAll: false), isFalse);
      expect(chatMessageMatchesKeywords(m, keywords: ['   '], matchAll: false),
          isFalse);
      // An empty keyword is dropped, leaving 'pizza' which matches (OR and AND).
      expect(chatMessageMatchesKeywords(m, keywords: ['', 'pizza'], matchAll: false),
          isTrue);
      expect(chatMessageMatchesKeywords(m, keywords: ['', 'pizza'], matchAll: true),
          isTrue,
          reason: 'AND must ignore the empty keyword, not fail on it');
    });
  });

  group('S93 isSearchableMessage', () {
    test('excludes control-signal carriers, allows normal messages', () {
      expect(isSearchableMessage(_msg('hello there')), isTrue);
      expect(isSearchableMessage(_msg('', fileName: 'doc.pdf', mediaKind: 'file')),
          isTrue);
      for (final prefix in kSearchControlSignalPrefixes) {
        expect(isSearchableMessage(_msg('${prefix}payload')), isFalse,
            reason: '$prefix is a control signal, not a searchable bubble');
      }
    });
  });

  group('S93 effectiveKeywords', () {
    test('trims, lower-cases, and drops empty/whitespace entries', () {
      expect(effectiveKeywords(['  Pizza ', '', '   ', 'SALAD']),
          <String>['pizza', 'salad']);
      expect(effectiveKeywords(<String>[]), isEmpty);
      expect(effectiveKeywords(['   ']), isEmpty);
    });
  });
}
