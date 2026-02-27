import 'package:asteroids_core/core.dart';
import 'package:test/test.dart';

class DummySubscriptionToken implements SubscriptionToken {
  bool isCanceled = false;

  @override
  void cancel() {
    isCanceled = true;
  }
}

class DummyEventBus implements EventBus {
  final List<Object> publishedEvents = <Object>[];
  final Map<Type, List<EventHandler>> _handlers = <Type, List<EventHandler>>{};

  @override
  void publish(Object event) {
    publishedEvents.add(event);
    final handlers = _handlers[event.runtimeType] ?? const <EventHandler>[];
    for (final handler in handlers) {
      handler(event);
    }
  }

  @override
  SubscriptionToken subscribe(Type type, EventHandler handler) {
    _handlers.putIfAbsent(type, () => <EventHandler>[]).add(handler);
    return DummySubscriptionToken();
  }
}

class DummyClock implements Clock {
  DummyClock(this.currentMs);

  int currentMs;

  void advance(Duration delta) {
    currentMs += delta.inMilliseconds;
  }

  @override
  int get nowMs => currentMs;
}

class DummyRng implements Rng {
  DummyRng(this.seed);

  @override
  final int seed;

  int _cursor = 0;

  @override
  int nextInt(int max) {
    _cursor++;
    return (_cursor + seed) % max;
  }

  @override
  double nextDouble() {
    _cursor++;
    return ((_cursor + seed) % 100) / 100;
  }
}

class DummyStorage implements Storage {
  final Map<String, Object> _data = <String, Object>{};

  @override
  Future<void> write(String key, Object value) async {
    _data[key] = value;
  }

  @override
  Future<Object?> read(String key) async => _data[key];

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }
}

class DummyWorld implements World {
  int _nextId = 1;
  final Set<EntityId> _entities = <EntityId>{};
  final Map<Type, Map<EntityId, Object>> _byType = <Type, Map<EntityId, Object>>{};

  @override
  Iterable<EntityId> get entities => _entities;

  @override
  EntityId createEntity() {
    final id = _nextId++;
    _entities.add(id);
    return id;
  }

  @override
  bool removeEntity(EntityId entity) {
    final removed = _entities.remove(entity);
    if (!removed) {
      return false;
    }
    for (final store in _byType.values) {
      store.remove(entity);
    }
    return true;
  }

  @override
  void attachComponent(EntityId entity, Object component) {
    _byType.putIfAbsent(component.runtimeType, () => <EntityId, Object>{})[entity] = component;
  }

  @override
  T? getComponent<T extends Object>(EntityId entity) {
    return _byType[T]?[entity] as T?;
  }

  @override
  bool hasComponent<T extends Object>(EntityId entity) {
    return _byType[T]?.containsKey(entity) ?? false;
  }

  @override
  void removeComponent<T extends Object>(EntityId entity) {
    _byType[T]?.remove(entity);
  }

  @override
  Iterable<EntityId> query(Iterable<Type> componentTypes) {
    final types = componentTypes.toList(growable: false);
    if (types.isEmpty) {
      return _entities;
    }
    final firstStore = _byType[types.first];
    if (firstStore == null) {
      return const <EntityId>[];
    }
    final result = <EntityId>[];
    for (final entity in firstStore.keys) {
      var ok = _entities.contains(entity);
      for (var i = 1; i < types.length && ok; i++) {
        if (!(_byType[types[i]]?.containsKey(entity) ?? false)) {
          ok = false;
        }
      }
      if (ok) {
        result.add(entity);
      }
    }
    return result;
  }
}

class DummyGameMode implements GameMode {
  DummyGameMode(this.id);

  @override
  final String id;

  int entered = 0;
  int updated = 0;
  int exited = 0;
  Duration lastDt = Duration.zero;

  @override
  void onEnter(GameContext context) {
    entered++;
  }

  @override
  void onUpdate(GameContext context, Duration dt) {
    updated++;
    lastDt = dt;
  }

  @override
  void onExit(GameContext context) {
    exited++;
  }
}

void main() {
  group('coreLabel', () {
    test('returns a stable shell label', () {
      expect(coreLabel(), 'Asteroids Core');
    });
  });

  group('contracts', () {
    test('can be instantiated and used with dummies', () async {
      final eventBus = DummyEventBus();
      final clock = DummyClock(1000);
      final rng = DummyRng(42);
      final storage = DummyStorage();
      final world = DummyWorld();
      final mode = DummyGameMode('shell');

      final context = GameContext(
        clock: clock,
        rng: rng,
        storage: storage,
        eventBus: eventBus,
        world: world,
      );

      var received = 0;
      final token = eventBus.subscribe(String, (event) {
        if (event is String) {
          received++;
        }
      });
      eventBus.publish('boot');

      await storage.write('mode', mode.id);
      final storedMode = await storage.read('mode');

      final entity = world.createEntity();
      world.attachComponent(entity, const <String, num>{'x': 0, 'y': 0});
      final removed = world.removeEntity(entity);

      final frame = RenderFrame(
        timestampMs: clock.nowMs,
        shapes: const <ShapeModel>[
          ShapeModel.circle(position: Vec2(10, 20), alpha: 1, radius: 8),
        ],
        hud: const HudModel(
          destroyed: 0,
          misses: 0,
          time: Duration.zero,
          paused: false,
        ),
        uiState: const UiState(
          showStartScreen: true,
          showPauseModal: false,
          showQuitModal: false,
        ),
      );

      mode.onEnter(context);
      mode.onExit(context);
      token.cancel();

      expect(received, 1);
      expect((token as DummySubscriptionToken).isCanceled, isTrue);
      expect(rng.nextInt(10), inInclusiveRange(0, 9));
      expect(rng.nextDouble(), inInclusiveRange(0, 1));
      expect(storedMode, 'shell');
      expect(removed, isTrue);
      expect(world.query(<Type>[Map<String, num>]), isEmpty);
      expect(frame.shapes.single.kind, ShapeKind.circle);
      expect(mode.entered, 1);
      expect(mode.exited, 1);
    });
  });

  group('sanity', () {
    test('EventBus delivers event to subscriber', () {
      final bus = DummyEventBus();
      String? received;

      bus.subscribe(String, (event) {
        received = event as String;
      });
      bus.publish('ping');

      expect(received, 'ping');
    });

    test('RNG with fixed seed is deterministic', () {
      final rngA = DummyRng(7);
      final rngB = DummyRng(7);

      final seqA = <int>[rngA.nextInt(100), rngA.nextInt(100), rngA.nextInt(100)];
      final seqB = <int>[rngB.nextInt(100), rngB.nextInt(100), rngB.nextInt(100)];

      expect(seqA, seqB);
    });

    test('fake clock advances time', () {
      final clock = DummyClock(1000);
      final expected = 1016;
      clock.advance(const Duration(milliseconds: 16));

      expect(clock.nowMs, expected);
    });
  });

  group('game engine', () {
    test('orchestrates update, tick and mode changes', () {
      final eventBus = DummyEventBus();
      final clock = DummyClock(1_000);
      final rng = DummyRng(11);
      final storage = DummyStorage();
      final world = DummyWorld();
      final modeA = DummyGameMode('menu');
      final modeB = DummyGameMode('gameplay');

      final engine = GameEngine(
        clock: clock,
        rng: rng,
        storage: storage,
        eventBus: eventBus,
        world: world,
        mode: modeA,
      );

      expect(engine.mode.id, 'menu');
      expect(modeA.entered, 1);
      expect(engine.world, same(world));
      expect(engine.eventBus, same(eventBus));
      expect(engine.state, GameLifecycleState.idle);

      eventBus.publish(const GameStartRequested());
      expect(engine.state, GameLifecycleState.running);

      engine.update(const Duration(milliseconds: 16));
      expect(modeA.updated, 1);
      expect(modeA.lastDt, const Duration(milliseconds: 16));
      expect(eventBus.publishedEvents.whereType<GameTick>().length, 1);

      engine.tick();
      clock.advance(const Duration(milliseconds: 20));
      engine.tick();
      final ticks = eventBus.publishedEvents.whereType<GameTick>().toList();
      expect(ticks.last.dt, const Duration(milliseconds: 20));

      engine.setMode(modeB);
      expect(modeA.exited, 1);
      expect(modeB.entered, 1);
      expect(engine.mode.id, 'gameplay');
      expect(eventBus.publishedEvents.whereType<GameModeChanged>().length, 1);

      eventBus.publish(const GamePauseToggleRequested());
      expect(engine.state, GameLifecycleState.paused);
      eventBus.publish(const GamePauseToggleRequested());
      expect(engine.state, GameLifecycleState.running);
      eventBus.publish(const GameQuitRequested());
      expect(engine.state, GameLifecycleState.quit);
      expect(eventBus.publishedEvents.whereType<GameStateChanged>(), isNotEmpty);
    });
  });

  group('classic mode ecs', () {
    test('spawns asteroid, handles hit, emits render frame', () {
      final eventBus = DummyEventBus();
      final clock = DummyClock(2_000);
      final world = EcsWorld();
      final mode = ClassicMode(
        config: const ClassicConfig(width: 800, height: 600, spawnCooldown: Duration.zero),
      );
      final engine = GameEngine(
        clock: clock,
        rng: DummyRng(1),
        storage: DummyStorage(),
        eventBus: eventBus,
        world: world,
        mode: mode,
      );
      eventBus.publish(const GameStartRequested());

      engine.update(const Duration(milliseconds: 16));
      final asteroidsAfterSpawn = world.query(<Type>[AsteroidTag]).toList();
      expect(asteroidsAfterSpawn.length, 1);
      expect(eventBus.publishedEvents.whereType<AsteroidSpawned>().length, 1);
      expect(mode.lastFrame.shapes, isNotEmpty);
      expect(eventBus.publishedEvents.whereType<RenderFrameReady>(), isNotEmpty);

      final asteroid = asteroidsAfterSpawn.single;
      final t = world.getComponent<Transform>(asteroid)!;
      eventBus.publish(
        InputPointerDown(
          x: t.x,
          y: t.y,
          timestampMs: clock.nowMs,
        ),
      );
      engine.update(const Duration(milliseconds: 16));

      expect(world.query(<Type>[AsteroidTag]), isEmpty);
      expect(eventBus.publishedEvents.whereType<AsteroidDestroyed>().length, 1);
      expect(eventBus.publishedEvents.whereType<ParticlesRequested>().length, 1);
      expect(eventBus.publishedEvents.whereType<StatsUpdated>(), isNotEmpty);
    });

    test('escape system despawns out-of-bounds asteroid and tracks stats', () {
      final eventBus = DummyEventBus();
      final world = EcsWorld();
      final mode = ClassicMode(
        config: const ClassicConfig(width: 100, height: 100, spawnCooldown: Duration(hours: 1)),
      );
      final engine = GameEngine(
        clock: DummyClock(3_000),
        rng: DummyRng(2),
        storage: DummyStorage(),
        eventBus: eventBus,
        world: world,
        mode: mode,
      );
      eventBus.publish(const GameStartRequested());

      final asteroid = world.createEntity();
      world.attachComponent(asteroid, const AsteroidTag());
      world.attachComponent(asteroid, Transform(x: 500, y: 500));
      world.attachComponent(asteroid, const EscapeBounds(padding: 10));
      world.attachComponent(asteroid, const ColliderCircle(r: 10));

      engine.update(const Duration(milliseconds: 16));

      expect(world.query(<Type>[AsteroidTag]), isEmpty);
      expect(eventBus.publishedEvents.whereType<AsteroidEscaped>().length, 1);
    });

    test('loads and saves lastResult via storage', () async {
      final eventBus = DummyEventBus();
      final storage = DummyStorage();
      await storage.write(
        ClassicMode.lastResultStorageKey,
        <String, Object>{
          'spawned': 2,
          'escaped': 1,
          'hits': 3,
          'misses': 4,
          'score': 30,
          'difficultyMultiplier': 1.0,
          'timeMs': 5000,
        },
      );

      final mode = ClassicMode(
        config: const ClassicConfig(width: 100, height: 100, spawnCooldown: Duration.zero),
      );
      final engine = GameEngine(
        clock: DummyClock(10_000),
        rng: DummyRng(3),
        storage: storage,
        eventBus: eventBus,
        world: EcsWorld(),
        mode: mode,
      );

      await mode.loadLastResultTask;
      expect(mode.lastLoadedResult?.score, 30);

      eventBus.publish(const GameStartRequested());
      engine.update(const Duration(milliseconds: 16));
      engine.dispose();
      await mode.saveLastResultTask;

      final saved = await storage.read(ClassicMode.lastResultStorageKey);
      expect(saved, isA<Map>());
      expect((saved as Map)['timeMs'], greaterThanOrEqualTo(16));
    });
  });

  group('simulation', () {
    test('determinism: same seed + same inputs => same final result', () async {
      Future<RunStatsSnapshot?> runScenario() async {
        final eventBus = DummyEventBus();
        final clock = DummyClock(1_000);
        final storage = DummyStorage();
        final mode = ClassicMode(
          config: const ClassicConfig(width: 300, height: 500, spawnCooldown: Duration.zero),
        );
        final engine = GameEngine(
          clock: clock,
          rng: SeededRng(12345),
          storage: storage,
          eventBus: eventBus,
          world: EcsWorld(),
          mode: mode,
        );

        eventBus.publish(const GameStartRequested());
        engine.update(const Duration(milliseconds: 16));
        final asteroid = engine.world.query(<Type>[AsteroidTag]).single;
        final t = engine.world.getComponent<Transform>(asteroid)!;
        eventBus.publish(
          InputPointerDown(
            x: t.x,
            y: t.y,
            timestampMs: clock.nowMs,
          ),
        );
        engine.update(const Duration(milliseconds: 16));

        engine.dispose();
        await mode.saveLastResultTask;
        final saved = await storage.read(ClassicMode.lastResultStorageKey);
        if (saved is! Map) {
          return null;
        }
        return RunStatsSnapshot(
          spawned: (saved['spawned'] as num).toInt(),
          escaped: (saved['escaped'] as num).toInt(),
          hits: (saved['hits'] as num).toInt(),
          misses: (saved['misses'] as num).toInt(),
          score: (saved['score'] as num).toInt(),
          difficultyMultiplier: (saved['difficultyMultiplier'] as num).toDouble(),
          time: Duration(milliseconds: (saved['timeMs'] as num).toInt()),
          paused: false,
        );
      }

      final first = await runScenario();
      final second = await runScenario();

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.spawned, second!.spawned);
      expect(first.hits, second.hits);
      expect(first.misses, second.misses);
      expect(first.escaped, second.escaped);
      expect(first.score, second.score);
      expect(first.time, second.time);
    });

    test('hit: pointer over asteroid => AsteroidDestroyed; outside => HitMissed', () {
      final eventBus = DummyEventBus();
      final clock = DummyClock(2_000);
      final mode = ClassicMode(
        config: const ClassicConfig(width: 300, height: 500, spawnCooldown: Duration.zero),
      );
      final engine = GameEngine(
        clock: clock,
        rng: SeededRng(77),
        storage: DummyStorage(),
        eventBus: eventBus,
        world: EcsWorld(),
        mode: mode,
      );

      eventBus.publish(const GameStartRequested());
      engine.update(const Duration(milliseconds: 16));
      final asteroid = engine.world.query(<Type>[AsteroidTag]).single;
      final t = engine.world.getComponent<Transform>(asteroid)!;

      eventBus.publish(InputPointerDown(x: t.x, y: t.y, timestampMs: clock.nowMs));
      engine.update(const Duration(milliseconds: 16));

      eventBus.publish(InputPointerDown(x: 9999, y: 9999, timestampMs: clock.nowMs));
      engine.update(const Duration(milliseconds: 16));

      expect(eventBus.publishedEvents.whereType<AsteroidDestroyed>(), isNotEmpty);
      expect(eventBus.publishedEvents.whereType<HitMissed>(), isNotEmpty);
    });

    test('escape: ticks until asteroid leaves bounds => AsteroidEscaped', () {
      final eventBus = DummyEventBus();
      final mode = ClassicMode(
        config: const ClassicConfig(width: 120, height: 120, spawnCooldown: Duration.zero),
      );
      final engine = GameEngine(
        clock: DummyClock(3_000),
        rng: SeededRng(99),
        storage: DummyStorage(),
        eventBus: eventBus,
        world: EcsWorld(),
        mode: mode,
      );

      eventBus.publish(const GameStartRequested());
      engine.update(const Duration(milliseconds: 16)); // spawn
      for (var i = 0; i < 250; i++) {
        engine.update(const Duration(milliseconds: 16));
      }

      expect(eventBus.publishedEvents.whereType<AsteroidEscaped>(), isNotEmpty);
    });

    test('persistence: finalize => storage receives saveLastResult', () async {
      final storage = DummyStorage();
      final eventBus = DummyEventBus();
      final mode = ClassicMode(
        config: const ClassicConfig(width: 200, height: 200, spawnCooldown: Duration.zero),
      );
      final engine = GameEngine(
        clock: DummyClock(4_000),
        rng: SeededRng(5),
        storage: storage,
        eventBus: eventBus,
        world: EcsWorld(),
        mode: mode,
      );

      eventBus.publish(const GameStartRequested());
      engine.update(const Duration(milliseconds: 16));
      engine.dispose();
      await mode.saveLastResultTask;

      final saved = await storage.read(ClassicMode.lastResultStorageKey);
      expect(saved, isA<Map>());
      expect((saved as Map).containsKey('score'), isTrue);
      expect(saved.containsKey('timeMs'), isTrue);
    });
  });
}
