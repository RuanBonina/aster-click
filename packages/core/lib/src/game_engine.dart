library;

import 'contracts.dart';
import 'game_events.dart';

class GameTick {
  const GameTick({
    required this.nowMs,
    required this.dt,
    required this.modeId,
  });

  final int nowMs;
  final Duration dt;
  final String modeId;
}

class GameModeChanged {
  const GameModeChanged({
    required this.previousModeId,
    required this.nextModeId,
  });

  final String previousModeId;
  final String nextModeId;
}

class GameEngine {
  GameEngine({
    required this.clock,
    required this.rng,
    required this.storage,
    required this.eventBus,
    required this.world,
    required GameMode mode,
  }) : _mode = mode,
       context = GameContext(
         clock: clock,
         rng: rng,
         storage: storage,
         eventBus: eventBus,
         world: world,
       ) {
    _startSub = eventBus.subscribe(GameStartRequested, (_) => _setState(GameLifecycleState.running));
    _pauseSub = eventBus.subscribe(GamePauseToggleRequested, (_) {
      if (_state == GameLifecycleState.running) {
        _setState(GameLifecycleState.paused);
      } else if (_state == GameLifecycleState.paused) {
        _setState(GameLifecycleState.running);
      }
    });
    _quitSub = eventBus.subscribe(GameQuitRequested, (_) => _setState(GameLifecycleState.quit));
    _mode.onEnter(context);
  }

  final Clock clock;
  final Rng rng;
  final Storage storage;
  final EventBus eventBus;
  final World world;
  final GameContext context;

  GameMode _mode;
  int? _lastTickMs;
  GameLifecycleState _state = GameLifecycleState.idle;
  late final SubscriptionToken _startSub;
  late final SubscriptionToken _pauseSub;
  late final SubscriptionToken _quitSub;

  GameMode get mode => _mode;
  int? get lastTickMs => _lastTickMs;
  GameLifecycleState get state => _state;

  void setMode(GameMode nextMode) {
    if (identical(_mode, nextMode)) {
      return;
    }

    final previous = _mode;
    previous.onExit(context);
    _mode = nextMode;
    _mode.onEnter(context);
    eventBus.publish(
      GameModeChanged(
        previousModeId: previous.id,
        nextModeId: nextMode.id,
      ),
    );
  }

  void _setState(GameLifecycleState next) {
    if (_state == next) {
      return;
    }
    final previous = _state;
    _state = next;
    eventBus.publish(GameStateChanged(previous: previous, current: next));
  }

  void update(Duration dt) {
    if (_state != GameLifecycleState.running) {
      return;
    }
    _mode.onUpdate(context, dt);
    eventBus.publish(
      GameTick(
        nowMs: clock.nowMs,
        dt: dt,
        modeId: _mode.id,
      ),
    );
  }

  void tick([int? nowMs]) {
    final currentMs = nowMs ?? clock.nowMs;
    final dt = _lastTickMs == null
        ? Duration.zero
        : Duration(milliseconds: currentMs - _lastTickMs!);
    _lastTickMs = currentMs;
    update(dt);
  }

  void dispose() {
    _startSub.cancel();
    _pauseSub.cancel();
    _quitSub.cancel();
    _mode.onExit(context);
  }
}
