import 'package:flutter_test/flutter_test.dart';

import 'package:toxee/util/disposable_bag.dart';

void main() {
  group('DisposableBag', () {
    test('dispose is idempotent', () {
      final bag = DisposableBag();
      var disposed = 0;
      bag.add(() => disposed++);
      bag.dispose();
      expect(disposed, 1);
      bag.dispose(); // second call is no-op
      expect(disposed, 1);
    });

    test('add after dispose throws', () {
      final bag = DisposableBag();
      bag.dispose();
      expect(
        () => bag.add(() {}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot add disposer after'),
        )),
      );
    });

    test('disposers run in reverse order', () {
      final bag = DisposableBag();
      final order = <int>[];
      bag.add(() => order.add(1));
      bag.add(() => order.add(2));
      bag.add(() => order.add(3));
      bag.dispose();
      expect(order, [3, 2, 1]);
    });

    test('exception in disposer does not stop others and is logged', () {
      final bag = DisposableBag();
      var secondCalled = false;
      bag.add(() => throw Exception('first'));
      bag.add(() => secondCalled = true);
      bag.dispose();
      expect(secondCalled, true);
    });
  });
}
