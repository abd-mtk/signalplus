import 'package:fpdart/fpdart.dart';

final class Memo<T> {
  Option<Future<T>> cached = const None();

  Future<T> call(final Future<T> Function() load) => cached.getOrElse(() {
    final Future<T> loaded = load().onError<Object>((final Object error, final StackTrace stack) {
      cached = const None();
      Error.throwWithStackTrace(error, stack);
    });
    cached = some(loaded);
    return loaded;
  });

  void set(final T value) => cached = some(Future<T>.value(value));

  void reset() => cached = const None();
}
