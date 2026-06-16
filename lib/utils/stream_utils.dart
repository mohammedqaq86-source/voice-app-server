import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wraps a Firestore stream to be safe for use in [StreamBuilder] on web.
///
/// Two problems are fixed here:
///
/// 1. **Race condition in cloud_firestore_web**: When a [StreamBuilder] disposes
///    it cancels its subscription synchronously, but the Firestore JS SDK sets
///    the `onSnapshotUnsubscribe` callback asynchronously. If the cancel arrives
///    before that callback is stored, a [LateInitializationError] is thrown.
///    Deferring the underlying cancel by one microtask lets Firestore finish
///    its setup before we unregister the listener.
///
/// 2. **Multiple [StreamBuilder] widgets on the same stream instance**: Firestore
///    streams are single-subscription. Passing the same [Stream] object to two
///    [StreamBuilder] widgets would fail. The broadcast controller here allows
///    unlimited listeners while keeping exactly one underlying Firestore
///    subscription.
///
/// On non-web platforms the stream is returned unchanged (no overhead).
Stream<T> safeFirestoreStream<T>(Stream<T> source) {
  if (!kIsWeb) return source;

  StreamSubscription<T>? sub;
  final controller = StreamController<T>.broadcast();

  controller.onListen = () {
    if (sub != null) return;
    sub = source.listen(
      (data) {
        if (!controller.isClosed) controller.add(data);
      },
      onError: (Object error, StackTrace st) {
        if (!controller.isClosed) controller.addError(error, st);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );
  };

  controller.onCancel = () {
    // Defer by one microtask so Firestore's onSnapshotUnsubscribe has time
    // to be initialized before we call it.
    Future.microtask(() => sub?.cancel());
  };

  return controller.stream;
}
