# asteroids_world monorepo

## Structure

```
packages/
  core/        # pure Dart game/domain core (no Flutter imports)
  app_flutter/ # Flutter shell application
```

## Commands

Core:

```
cd packages/core
dart test
```

Flutter app:

```
cd packages/app_flutter
flutter pub get
flutter test
flutter run -d android
```
