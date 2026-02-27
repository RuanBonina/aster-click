import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:asteroids_core/core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asteroids World',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A84FF)),
      ),
      home: const ShellScreen(),
    );
  }
}

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  static const bool _useFixedSeed = bool.fromEnvironment('FIXED_SEED', defaultValue: false);
  static const int _fixedSeedValue = int.fromEnvironment('FIXED_SEED_VALUE', defaultValue: 42);

  static const String _settingsKey = 'classic.settings';

  late final Clock _clock;
  late final LocalEventBus _eventBus;
  final List<SubscriptionToken> _subscriptions = <SubscriptionToken>[];

  GameEngine? _engine;
  ClassicMode? _classicMode;
  Timer? _loopTimer;
  int _seed = 0;
  bool _ready = false;

  GameLifecycleState _state = GameLifecycleState.idle;
  RenderFrame _frame = const RenderFrame(
    timestampMs: 0,
    shapes: <ShapeModel>[],
    hud: HudModel(destroyed: 0, misses: 0, time: Duration.zero, paused: false),
    uiState: UiState(showStartScreen: true, showPauseModal: false, showQuitModal: false),
  );
  RunStatsSnapshot _stats = const RunStatsSnapshot(
    spawned: 0,
    escaped: 0,
    hits: 0,
    misses: 0,
    score: 0,
    difficultyMultiplier: 1,
    time: Duration.zero,
    paused: false,
  );
  RunStatsSnapshot? _lastResult;
  String _lastFact = 'none';

  double _uiOpacity = 1;
  int _speedLevel = 3;
  bool _difficultyProgression = true;
  bool _showCustomize = false;
  bool _showQuitConfirm = false;

  @override
  void initState() {
    super.initState();
    _clock = _StopwatchClock();
    _eventBus = LocalEventBus();
    unawaited(_initEngine());
  }

  Future<void> _initEngine() async {
    Storage storage;
    try {
      final prefs = await SharedPreferences.getInstance();
      storage = _SharedPrefsStorage(prefs);
    } catch (_) {
      storage = _MemoryStorage();
    }
    final savedSettings = await storage.read(_settingsKey);
    if (savedSettings is Map) {
      _uiOpacity = ((savedSettings['uiOpacity'] as num?) ?? 1).toDouble().clamp(0.2, 1);
      _speedLevel = ((savedSettings['speedLevel'] as num?) ?? 3).toInt().clamp(1, 5);
      _difficultyProgression = (savedSettings['difficultyProgression'] as bool?) ?? true;
    }

    _seed = _useFixedSeed ? _fixedSeedValue : Random().nextInt(1 << 31);
    final mode = ClassicMode(config: const ClassicConfig(width: 360, height: 640));
    final engine = GameEngine(
      clock: _clock,
      rng: SeededRng(_seed),
      storage: storage,
      eventBus: _eventBus,
      world: EcsWorld(),
      mode: mode,
    );

    _subscriptions.addAll(<SubscriptionToken>[
      _eventBus.subscribe(RenderFrameReady, (event) {
        if (!mounted) {
          return;
        }
        setState(() => _frame = (event as RenderFrameReady).frame);
      }),
      _eventBus.subscribe(GameStateChanged, (event) {
        if (!mounted) {
          return;
        }
        final state = (event as GameStateChanged).current;
        setState(() => _state = state);
      }),
      _eventBus.subscribe(AsteroidDestroyed, (_) {
        if (!mounted) {
          return;
        }
        setState(() => _lastFact = 'asteroid.destroyed');
      }),
      _eventBus.subscribe(HitMissed, (_) {
        if (!mounted) {
          return;
        }
        setState(() => _lastFact = 'hit.missed');
      }),
      _eventBus.subscribe(AsteroidEscaped, (_) {
        if (!mounted) {
          return;
        }
        setState(() => _lastFact = 'asteroid.escaped');
      }),
      _eventBus.subscribe(StatsUpdated, (event) {
        if (!mounted) {
          return;
        }
        setState(() => _stats = (event as StatsUpdated).stats);
      }),
    ]);

    _publishSettings();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => engine.tick());

    await mode.loadLastResultTask;
    if (!mounted) {
      _loopTimer?.cancel();
      engine.dispose();
      return;
    }

    setState(() {
      _classicMode = mode;
      _engine = engine;
      _lastResult = mode.lastLoadedResult;
      _ready = true;
    });
  }

  void _publishSettings() {
    _eventBus.publish(
      GameSettingsUpdatedRequested(
        uiOpacity: _uiOpacity,
        asteroidSpeedLevel: _speedLevel,
        difficultyProgression: _difficultyProgression,
      ),
    );
  }

  Future<void> _saveSettings() async {
    Storage storage;
    try {
      final prefs = await SharedPreferences.getInstance();
      storage = _SharedPrefsStorage(prefs);
    } catch (_) {
      storage = _MemoryStorage();
    }
    await storage.write(
      _settingsKey,
      <String, Object>{
        'uiOpacity': _uiOpacity,
        'speedLevel': _speedLevel,
        'difficultyProgression': _difficultyProgression,
      },
    );
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _engine?.dispose();
    super.dispose();
  }

  void _onStart() {
    _eventBus.publish(const GameStartRequested());
  }

  void _onPauseToggle() {
    _eventBus.publish(const GamePauseToggleRequested());
  }

  void _onQuitRequested() {
    setState(() {
      _showQuitConfirm = true;
    });
    if (_state == GameLifecycleState.running) {
      _eventBus.publish(const GamePauseToggleRequested());
    }
  }

  Future<void> _confirmQuit() async {
    setState(() => _showQuitConfirm = false);
    final mode = _classicMode;
    final engine = _engine;
    if (engine != null) {
      _eventBus.publish(const GameQuitRequested());
      engine.dispose();
      await mode?.saveLastResultTask;
      _loopTimer?.cancel();
      _loopTimer = null;
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _engine = null;
      _classicMode = null;
      if (mounted) {
        setState(() => _ready = false);
      }
      await _initEngine();
    }
  }

  void _cancelQuit() {
    setState(() => _showQuitConfirm = false);
    if (_state == GameLifecycleState.paused) {
      _eventBus.publish(const GamePauseToggleRequested());
    }
  }

  Future<void> _applySettings() async {
    _publishSettings();
    await _saveSettings();
    setState(() => _showCustomize = false);
  }

  void _publishPointer(TapDownDetails details) {
    _eventBus.publish(
      InputPointerDown(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
        timestampMs: _clock.nowMs,
      ),
    );
  }

  String _lastResultText() {
    final r = _lastResult;
    if (r == null) {
      return 'Ultima partida: (ainda nao jogada)';
    }
    final clicks = r.hits + r.misses;
    final acc = clicks == 0 ? 0 : ((r.hits / clicks) * 100).round();
    return 'Ultima partida\n'
        'Destruidos: ${r.hits}\n'
        'Fugas: ${r.escaped}\n'
        'Cliques: $clicks\n'
        'Precisao: $acc%\n'
        'Tempo: ${r.time.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Carregando...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final showStart = _state == GameLifecycleState.idle || _state == GameLifecycleState.quit;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTapDown: _publishPointer,
              child: CustomPaint(
                painter: _FramePainter(_frame),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 12,
            right: 12,
            child: Opacity(
              opacity: _uiOpacity,
              child: _HudBar(stats: _stats, lastFact: _lastFact),
            ),
          ),
          if (!showStart)
            Positioned(
              top: 16,
              right: 12,
              child: Opacity(
                opacity: _uiOpacity,
                child: Row(
                  children: <Widget>[
                    _IconPill(icon: Icons.pause, onTap: _onPauseToggle),
                    const SizedBox(width: 8),
                    _IconPill(icon: Icons.close, onTap: _onQuitRequested),
                  ],
                ),
              ),
            ),
          if (showStart) _buildStartOverlay(),
          if (_showCustomize) _buildSettingsModal(),
          if (_showQuitConfirm) _buildQuitConfirmModal(),
        ],
      ),
    );
  }

  Widget _buildStartOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        alignment: Alignment.center,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Asteroids World',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _IconPill(
                    icon: Icons.settings,
                    onTap: () => setState(() => _showCustomize = true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Destrua o asteroide antes que ele fuja da tela.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(_lastResultText(), style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _onStart,
                  child: const Text('Iniciar'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '1 hit kill • 1 asteroide por vez\nClique para destruir\nEsc pausa/retoma • X encerra',
                style: TextStyle(color: Colors.white54, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsModal() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Personalizar',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                    _IconPill(icon: Icons.arrow_back, onTap: () => setState(() => _showCustomize = false)),
                  ],
                ),
                const SizedBox(height: 14),
                _SliderRow(
                  label: 'Transparencia UI',
                  value: _uiOpacity * 100,
                  min: 20,
                  max: 100,
                  divisions: 4,
                  suffix: '${(_uiOpacity * 100).round()}%',
                  onChanged: (v) => setState(() => _uiOpacity = (v / 100).clamp(0.2, 1)),
                ),
                const SizedBox(height: 10),
                _SliderRow(
                  label: 'Velocidade',
                  value: _speedLevel.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  suffix: 'Nivel $_speedLevel',
                  onChanged: (v) => setState(() => _speedLevel = v.round().clamp(1, 5)),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: _difficultyProgression,
                  title: const Text('Dificuldade progressiva', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('A velocidade cresce com o tempo', style: TextStyle(color: Colors.white70)),
                  onChanged: (v) => setState(() => _difficultyProgression = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _applySettings,
                    child: const Text('Aplicar alteracoes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuitConfirmModal() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Encerrar partida?',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    _IconPill(icon: Icons.close, onTap: _cancelQuit),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seu desempenho sera salvo como "Ultima partida".',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancelQuit,
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                        onPressed: _confirmQuit,
                        child: const Text('Encerrar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HudBar extends StatelessWidget {
  const _HudBar({required this.stats, required this.lastFact});

  final RunStatsSnapshot stats;
  final String lastFact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Destroyed ${stats.hits} | Miss ${stats.misses} | Time ${stats.time.inSeconds}s',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Text(lastFact, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(color: Colors.white)),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(suffix, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _StopwatchClock implements Clock {
  _StopwatchClock() : _baseMs = DateTime.now().millisecondsSinceEpoch {
    _stopwatch.start();
  }

  final int _baseMs;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  int get nowMs => _baseMs + _stopwatch.elapsedMilliseconds;
}

class _SharedPrefsStorage implements Storage {
  _SharedPrefsStorage(this._prefs);

  static const String _jsonPrefix = '__json__:';
  final SharedPreferences _prefs;

  @override
  Future<void> clear() async {
    await _prefs.clear();
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }

  @override
  Future<Object?> read(String key) async {
    final value = _prefs.get(key);
    if (value is String && value.startsWith(_jsonPrefix)) {
      return jsonDecode(value.substring(_jsonPrefix.length));
    }
    return value;
  }

  @override
  Future<void> write(String key, Object value) async {
    if (value is int) {
      await _prefs.setInt(key, value);
      return;
    }
    if (value is double) {
      await _prefs.setDouble(key, value);
      return;
    }
    if (value is bool) {
      await _prefs.setBool(key, value);
      return;
    }
    if (value is String) {
      await _prefs.setString(key, value);
      return;
    }
    if (value is List<String>) {
      await _prefs.setStringList(key, value);
      return;
    }
    await _prefs.setString(key, '$_jsonPrefix${jsonEncode(value)}');
  }
}

class _MemoryStorage implements Storage {
  final Map<String, Object> _data = <String, Object>{};

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<Object?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Object value) async => _data[key] = value;
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);

  final RenderFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF030712);
    canvas.drawRect(Offset.zero & size, bg);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..style = PaintingStyle.fill;

    for (final shape in frame.shapes) {
      final alpha = (shape.alpha.clamp(0, 1) * 255).toInt();
      stroke.color = Color.fromARGB(alpha, 230, 230, 230);
      fill.color = Color.fromARGB((alpha * 0.15).toInt(), 230, 230, 230);

      switch (shape.kind) {
        case ShapeKind.circle:
          final c = Offset(shape.position.x, shape.position.y);
          canvas.drawCircle(c, shape.radius, fill);
          canvas.drawCircle(c, shape.radius, stroke);
          break;
        case ShapeKind.line:
          if (shape.points.length >= 2) {
            canvas.drawLine(
              Offset(shape.points.first.x, shape.points.first.y),
              Offset(shape.points.last.x, shape.points.last.y),
              stroke,
            );
          }
          break;
        case ShapeKind.polygon:
          if (shape.points.length >= 3) {
            final path = ui.Path()..moveTo(shape.points.first.x, shape.points.first.y);
            for (final p in shape.points.skip(1)) {
              path.lineTo(p.x, p.y);
            }
            path.close();
            canvas.drawPath(path, fill);
            canvas.drawPath(path, stroke);
          }
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) => oldDelegate.frame != frame;
}
