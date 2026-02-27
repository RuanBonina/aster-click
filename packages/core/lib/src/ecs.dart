library;

import 'contracts.dart';

class Transform {
  Transform({
    required this.x,
    required this.y,
    this.rot = 0,
  });

  double x;
  double y;
  double rot;
}

class Velocity {
  Velocity({
    required this.vx,
    required this.vy,
    this.angVel = 0,
  });

  double vx;
  double vy;
  double angVel;
}

class ColliderCircle {
  const ColliderCircle({required this.r});

  final double r;
}

class AsteroidTag {
  const AsteroidTag();
}

class EscapeBounds {
  const EscapeBounds({required this.padding});

  final double padding;
}

class Lifetime {
  Lifetime({required this.remaining});

  Duration remaining;
}

class RunStats {
  RunStats({
    this.spawned = 0,
    this.escaped = 0,
    this.hits = 0,
    this.misses = 0,
    this.score = 0,
    this.spawnCooldown = Duration.zero,
    this.difficultyMultiplier = 1,
    this.elapsed = Duration.zero,
  });

  int spawned;
  int escaped;
  int hits;
  int misses;
  int score;
  Duration spawnCooldown;
  double difficultyMultiplier;
  Duration elapsed;
}

class AsteroidSpawned {
  const AsteroidSpawned({required this.entity});

  final EntityId entity;
}

class AsteroidEscaped {
  const AsteroidEscaped({required this.entity});

  final EntityId entity;
}

class ParticlesRequested {
  const ParticlesRequested({
    required this.x,
    required this.y,
    required this.kind,
  });

  final double x;
  final double y;
  final String kind;
}

class EcsWorld implements World {
  final Set<EntityId> _entities = <EntityId>{};
  final Map<Type, Map<EntityId, Object>> _byType = <Type, Map<EntityId, Object>>{};
  EntityId _nextId = 1;

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
    if (!_entities.contains(entity)) {
      throw StateError('Entity $entity does not exist.');
    }
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
        final store = _byType[types[i]];
        if (store == null || !store.containsKey(entity)) {
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
