library;

import 'contracts.dart';

class LocalEventBus implements EventBus {
  final Map<Type, Map<int, EventHandler>> _handlers = <Type, Map<int, EventHandler>>{};
  int _nextId = 1;

  @override
  void publish(Object event) {
    final handlers = _handlers[event.runtimeType];
    if (handlers == null) {
      return;
    }
    for (final handler in handlers.values.toList(growable: false)) {
      handler(event);
    }
  }

  @override
  SubscriptionToken subscribe(Type type, EventHandler handler) {
    final id = _nextId++;
    final typeHandlers = _handlers.putIfAbsent(type, () => <int, EventHandler>{});
    typeHandlers[id] = handler;
    return _LocalSubscriptionToken(
      cancelFn: () {
        final handlers = _handlers[type];
        handlers?.remove(id);
        if (handlers != null && handlers.isEmpty) {
          _handlers.remove(type);
        }
      },
    );
  }
}

class _LocalSubscriptionToken implements SubscriptionToken {
  _LocalSubscriptionToken({required void Function() cancelFn}) : _cancelFn = cancelFn;

  final void Function() _cancelFn;
  bool _isCanceled = false;

  @override
  void cancel() {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    _cancelFn();
  }
}
