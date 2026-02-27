library;

typedef EntityId = int;
typedef EventHandler = void Function(Object event);

abstract interface class EventBus {
  void publish(Object event);
  SubscriptionToken subscribe(Type type, EventHandler handler);
}

abstract interface class SubscriptionToken {
  void cancel();
}

abstract interface class Clock {
  int get nowMs;
}

abstract interface class Rng {
  int get seed;
  int nextInt(int max);
  double nextDouble();
}

abstract interface class Storage {
  Future<void> write(String key, Object value);
  Future<Object?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();
}

abstract interface class GameMode {
  String get id;
  void onEnter(GameContext context);
  void onUpdate(GameContext context, Duration dt);
  void onExit(GameContext context);
}

class GameContext {
  GameContext({
    required this.clock,
    required this.rng,
    required this.storage,
    required this.eventBus,
    required this.world,
  });

  final Clock clock;
  final Rng rng;
  final Storage storage;
  final EventBus eventBus;
  final World world;
}

abstract interface class World {
  Iterable<EntityId> get entities;
  EntityId createEntity();
  bool removeEntity(EntityId entity);
  void attachComponent(EntityId entity, Object component);
  T? getComponent<T extends Object>(EntityId entity);
  bool hasComponent<T extends Object>(EntityId entity);
  void removeComponent<T extends Object>(EntityId entity);
  Iterable<EntityId> query(Iterable<Type> componentTypes);
}

class RenderFrame {
  const RenderFrame({
    required this.timestampMs,
    required this.shapes,
    required this.hud,
    required this.uiState,
  });

  final int timestampMs;
  final List<ShapeModel> shapes;
  final HudModel hud;
  final UiState uiState;
}

enum ShapeKind {
  circle,
  polygon,
  line,
}

class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;
}

class ShapeModel {
  const ShapeModel.circle({
    required this.position,
    required this.alpha,
    required this.radius,
  }) : kind = ShapeKind.circle,
       points = const <Vec2>[];

  const ShapeModel.polygon({
    required this.points,
    required this.alpha,
  }) : kind = ShapeKind.polygon,
       position = const Vec2(0, 0),
       radius = 0;

  const ShapeModel.line({
    required this.points,
    required this.alpha,
  }) : kind = ShapeKind.line,
       position = const Vec2(0, 0),
       radius = 0;

  final ShapeKind kind;
  final Vec2 position;
  final List<Vec2> points;
  final double radius;
  final double alpha;
}

class HudModel {
  const HudModel({
    required this.destroyed,
    required this.misses,
    required this.time,
    required this.paused,
  });

  final int destroyed;
  final int misses;
  final Duration time;
  final bool paused;
}

class UiState {
  const UiState({
    required this.showStartScreen,
    required this.showPauseModal,
    required this.showQuitModal,
  });

  final bool showStartScreen;
  final bool showPauseModal;
  final bool showQuitModal;
}
