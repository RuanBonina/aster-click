library;

import 'dart:async';

import 'contracts.dart';
import 'ecs.dart';
import 'game_events.dart';

class ClassicConfig {
  const ClassicConfig({
    required this.width,
    required this.height,
    this.spawnCooldown,
    this.spawnCooldownMin = const Duration(milliseconds: 200),
    this.spawnCooldownMax = const Duration(milliseconds: 500),
    this.baseAsteroidSpeed = 72,
    this.asteroidRadius = 18,
    this.escapePadding = 120,
    this.scorePerHit = 10,
    this.defaultSpeedLevel = 3,
    this.defaultDifficultyProgression = true,
    this.defaultUiOpacity = 1,
  });

  final double width;
  final double height;
  final Duration? spawnCooldown;
  final Duration spawnCooldownMin;
  final Duration spawnCooldownMax;
  final double baseAsteroidSpeed;
  final double asteroidRadius;
  final double escapePadding;
  final int scorePerHit;
  final int defaultSpeedLevel;
  final bool defaultDifficultyProgression;
  final double defaultUiOpacity;
}

class ClassicMode implements GameMode {
  ClassicMode({required this.config});

  @override
  String get id => 'classic';

  final ClassicConfig config;
  final List<InputPointerDown> _pendingPointerDown = <InputPointerDown>[];

  static const String lastResultStorageKey = 'classic.lastResult';
  SubscriptionToken? _inputSub;
  SubscriptionToken? _stateSub;
  SubscriptionToken? _settingsSub;
  EntityId? _runEntity;
  GameLifecycleState _currentState = GameLifecycleState.idle;
  int _speedLevel = 3;
  bool _difficultyProgression = true;
  double _uiOpacity = 1;
  Future<void> _loadLastResultTask = Future<void>.value();
  Future<void>? _saveLastResultTask;
  RunStatsSnapshot? _lastLoadedResult;
  RenderFrame _lastFrame = RenderFrame(
    timestampMs: 0,
    shapes: const <ShapeModel>[],
    hud: const HudModel(destroyed: 0, misses: 0, time: Duration.zero, paused: false),
    uiState: const UiState(showStartScreen: true, showPauseModal: false, showQuitModal: false),
  );

  RenderFrame get lastFrame => _lastFrame;
  Future<void> get loadLastResultTask => _loadLastResultTask;
  Future<void>? get saveLastResultTask => _saveLastResultTask;
  RunStatsSnapshot? get lastLoadedResult => _lastLoadedResult;

  @override
  void onEnter(GameContext context) {
    _speedLevel = config.defaultSpeedLevel;
    _difficultyProgression = config.defaultDifficultyProgression;
    _uiOpacity = config.defaultUiOpacity;
    _runEntity = context.world.createEntity();
    context.world.attachComponent(_runEntity!, RunStats());
    _inputSub = context.eventBus.subscribe(InputPointerDown, (event) {
      _pendingPointerDown.add(event as InputPointerDown);
    });
    _stateSub = context.eventBus.subscribe(GameStateChanged, (event) {
      final changed = event as GameStateChanged;
      _currentState = changed.current;
      final stats = _safeStats(context);
      if (stats != null) {
        _publishRenderSnapshot(context, stats);
      }
    });
    _settingsSub = context.eventBus.subscribe(GameSettingsUpdatedRequested, (event) {
      final settings = event as GameSettingsUpdatedRequested;
      _speedLevel = settings.asteroidSpeedLevel.clamp(1, 5).toInt();
      _difficultyProgression = settings.difficultyProgression;
      _uiOpacity = settings.uiOpacity.clamp(0.2, 1).toDouble();
    });
    _loadLastResultTask = _loadLastResult(context);
    _publishRenderSnapshot(context, _stats(context));
  }

  @override
  void onUpdate(GameContext context, Duration dt) {
    final stats = _stats(context);
    stats.elapsed += dt;

    _difficultySystem(stats);
    _spawnSystem(context, stats, dt);
    _movementSystem(context, dt);
    _escapeSystem(context);
    _hitSystem(context);
    _statsSystem(context, stats);
    _publishRenderSnapshot(context, stats);
  }

  @override
  void onExit(GameContext context) {
    _saveLastResultTask = _saveLastResult(context);
    unawaited(_saveLastResultTask);
    _inputSub?.cancel();
    _inputSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _settingsSub?.cancel();
    _settingsSub = null;
  }

  Future<void> _loadLastResult(GameContext context) async {
    final raw = await context.storage.read(lastResultStorageKey);
    if (raw is! Map) {
      return;
    }
    int readInt(String key) => (raw[key] as num?)?.toInt() ?? 0;
    _lastLoadedResult = RunStatsSnapshot(
      spawned: readInt('spawned'),
      escaped: readInt('escaped'),
      hits: readInt('hits'),
      misses: readInt('misses'),
      score: readInt('score'),
      difficultyMultiplier: (raw['difficultyMultiplier'] as num?)?.toDouble() ?? 1,
      time: Duration(milliseconds: readInt('timeMs')),
      paused: false,
    );
  }

  Future<void> _saveLastResult(GameContext context) async {
    final stats = _safeStats(context);
    if (stats == null) {
      return;
    }
    await context.storage.write(
      lastResultStorageKey,
      <String, Object>{
        'spawned': stats.spawned,
        'escaped': stats.escaped,
        'hits': stats.hits,
        'misses': stats.misses,
        'score': stats.score,
        'difficultyMultiplier': stats.difficultyMultiplier,
        'timeMs': stats.elapsed.inMilliseconds,
      },
    );
  }

  RunStats? _safeStats(GameContext context) {
    final run = _runEntity;
    if (run == null) {
      return null;
    }
    return context.world.getComponent<RunStats>(run);
  }

  RunStats _stats(GameContext context) {
    final stats = _safeStats(context);
    if (stats == null) {
      throw StateError('RunStats missing on run entity.');
    }
    return stats;
  }

  void _difficultySystem(RunStats stats) {
    const speedMap = <double>[1, 1.5, 2, 3, 4];
    final base = speedMap[_speedLevel.clamp(1, 5).toInt() - 1];
    if (_difficultyProgression) {
      final step = (stats.elapsed.inSeconds ~/ 10) * 0.1;
      stats.difficultyMultiplier = (base + step).clamp(base, 3.0);
      return;
    }
    stats.difficultyMultiplier = base;
  }

  Duration _randomSpawnCooldown(GameContext context) {
    if (config.spawnCooldown != null) {
      return config.spawnCooldown!;
    }
    final minMs = config.spawnCooldownMin.inMilliseconds;
    final maxMs = config.spawnCooldownMax.inMilliseconds;
    if (maxMs <= minMs) {
      return Duration(milliseconds: minMs);
    }
    final delta = maxMs - minMs;
    return Duration(milliseconds: minMs + context.rng.nextInt(delta + 1));
  }

  void _spawnSystem(GameContext context, RunStats stats, Duration dt) {
    if (stats.spawnCooldown > Duration.zero) {
      final next = stats.spawnCooldown - dt;
      stats.spawnCooldown = next.isNegative ? Duration.zero : next;
    }

    final asteroidExists = context.world.query(<Type>[AsteroidTag]).isNotEmpty;
    if (asteroidExists || stats.spawnCooldown > Duration.zero) {
      return;
    }

    final entity = context.world.createEntity();
    final x = context.rng.nextDouble() * config.width;
    final y = -config.asteroidRadius;
    final speed = config.baseAsteroidSpeed * stats.difficultyMultiplier;
    context.world.attachComponent(entity, AsteroidTag());
    context.world.attachComponent(entity, Transform(x: x, y: y));
    context.world.attachComponent(entity, Velocity(vx: 0, vy: speed, angVel: 0.4));
    context.world.attachComponent(entity, ColliderCircle(r: config.asteroidRadius));
    context.world.attachComponent(entity, EscapeBounds(padding: config.escapePadding));
    stats.spawned++;
    stats.spawnCooldown = _randomSpawnCooldown(context);
    context.eventBus.publish(AsteroidSpawned(entity: entity));
  }

  void _movementSystem(GameContext context, Duration dt) {
    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    for (final entity in context.world.query(<Type>[Transform, Velocity])) {
      final t = context.world.getComponent<Transform>(entity);
      final v = context.world.getComponent<Velocity>(entity);
      if (t == null || v == null) {
        continue;
      }
      t.x += v.vx * seconds;
      t.y += v.vy * seconds;
      t.rot += v.angVel * seconds;
    }
  }

  void _escapeSystem(GameContext context) {
    final toRemove = <EntityId>[];
    for (final entity in context.world.query(<Type>[AsteroidTag, Transform, EscapeBounds])) {
      final t = context.world.getComponent<Transform>(entity);
      final b = context.world.getComponent<EscapeBounds>(entity);
      if (t == null || b == null) {
        continue;
      }
      final escaped =
          t.x < -b.padding ||
          t.x > config.width + b.padding ||
          t.y < -b.padding ||
          t.y > config.height + b.padding;
      if (escaped) {
        toRemove.add(entity);
      }
    }

    final stats = _stats(context);
    for (final entity in toRemove) {
      if (context.world.removeEntity(entity)) {
        stats.escaped++;
        context.eventBus.publish(AsteroidEscaped(entity: entity));
      }
    }
  }

  void _hitSystem(GameContext context) {
    if (_pendingPointerDown.isEmpty) {
      return;
    }

    final stats = _stats(context);
    final inputs = List<InputPointerDown>.from(_pendingPointerDown);
    _pendingPointerDown.clear();

    for (final pointer in inputs) {
      var hit = false;
      for (final entity in context.world.query(<Type>[AsteroidTag, Transform, ColliderCircle])) {
        final t = context.world.getComponent<Transform>(entity);
        final c = context.world.getComponent<ColliderCircle>(entity);
        if (t == null || c == null) {
          continue;
        }
        final dx = pointer.x - t.x;
        final dy = pointer.y - t.y;
        if ((dx * dx) + (dy * dy) <= c.r * c.r) {
          if (context.world.removeEntity(entity)) {
            stats.hits++;
            stats.score += config.scorePerHit;
            stats.spawnCooldown = _randomSpawnCooldown(context);
            context.eventBus.publish(AsteroidDestroyed(entity: entity, x: pointer.x, y: pointer.y));
            context.eventBus.publish(
              ParticlesRequested(
                x: pointer.x,
                y: pointer.y,
                kind: 'asteroid-hit',
              ),
            );
            hit = true;
          }
          break;
        }
      }
      if (!hit) {
        stats.misses++;
        context.eventBus.publish(
          HitMissed(
            x: pointer.x,
            y: pointer.y,
            timestampMs: pointer.timestampMs,
          ),
        );
      }
    }
  }

  void _statsSystem(GameContext context, RunStats stats) {
    context.eventBus.publish(
      StatsUpdated(
        RunStatsSnapshot(
          spawned: stats.spawned,
          escaped: stats.escaped,
          hits: stats.hits,
          misses: stats.misses,
          score: stats.score,
          difficultyMultiplier: stats.difficultyMultiplier,
          time: stats.elapsed,
          paused: _currentState == GameLifecycleState.paused,
        ),
      ),
    );
  }

  void _publishRenderSnapshot(GameContext context, RunStats stats) {
    final shapes = <ShapeModel>[];
    for (final entity in context.world.query(<Type>[AsteroidTag, Transform, ColliderCircle])) {
      final t = context.world.getComponent<Transform>(entity);
      final c = context.world.getComponent<ColliderCircle>(entity);
      if (t == null || c == null) {
        continue;
      }
      shapes.add(
        ShapeModel.circle(
          position: Vec2(t.x, t.y),
          radius: c.r,
          alpha: _uiOpacity,
        ),
      );
    }

    _lastFrame = RenderFrame(
      timestampMs: context.clock.nowMs,
      shapes: shapes,
      hud: HudModel(
        destroyed: stats.hits,
        misses: stats.misses,
        time: stats.elapsed,
        paused: _currentState == GameLifecycleState.paused,
      ),
      uiState: UiState(
        showStartScreen: _currentState == GameLifecycleState.idle,
        showPauseModal: _currentState == GameLifecycleState.paused,
        showQuitModal: _currentState == GameLifecycleState.quit,
      ),
    );
    context.eventBus.publish(RenderFrameReady(_lastFrame));
  }
}
