library;

import 'contracts.dart';

enum GameLifecycleState {
  idle,
  running,
  paused,
  quit,
}

class InputPointerDown {
  const InputPointerDown({
    required this.x,
    required this.y,
    required this.timestampMs,
  });

  final double x;
  final double y;
  final int timestampMs;
}

class GameStartRequested {
  const GameStartRequested();
}

class GamePauseToggleRequested {
  const GamePauseToggleRequested();
}

class GameQuitRequested {
  const GameQuitRequested();
}

class GameSettingsUpdatedRequested {
  const GameSettingsUpdatedRequested({
    required this.uiOpacity,
    required this.asteroidSpeedLevel,
    required this.difficultyProgression,
  });

  final double uiOpacity;
  final int asteroidSpeedLevel;
  final bool difficultyProgression;
}

class RenderFrameReady {
  const RenderFrameReady(this.frame);

  final RenderFrame frame;
}

class GameStateChanged {
  const GameStateChanged({
    required this.previous,
    required this.current,
  });

  final GameLifecycleState previous;
  final GameLifecycleState current;
}

class AsteroidDestroyed {
  const AsteroidDestroyed({
    required this.entity,
    required this.x,
    required this.y,
  });

  final EntityId entity;
  final double x;
  final double y;
}

class HitMissed {
  const HitMissed({
    required this.x,
    required this.y,
    required this.timestampMs,
  });

  final double x;
  final double y;
  final int timestampMs;
}

class StatsUpdated {
  const StatsUpdated(this.stats);

  final RunStatsSnapshot stats;
}

class RunStatsSnapshot {
  const RunStatsSnapshot({
    required this.spawned,
    required this.escaped,
    required this.hits,
    required this.misses,
    required this.score,
    required this.difficultyMultiplier,
    required this.time,
    required this.paused,
  });

  final int spawned;
  final int escaped;
  final int hits;
  final int misses;
  final int score;
  final double difficultyMultiplier;
  final Duration time;
  final bool paused;
}
