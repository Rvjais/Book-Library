import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/app_theme.dart';
import '../../data/library_repository.dart';
import '../../data/settings_repository.dart';
import '../identity/data/peer_identity.dart';
import '../p2p/p2p_service.dart';

/// Starts the app immediately and shows the animated brand splash while the
/// database and preferences load. Previously `main()` awaited everything before
/// `runApp`, so the user only ever saw the static platform launch icon.
class LibReadyBootstrap extends StatefulWidget {
  const LibReadyBootstrap({super.key});

  @override
  State<LibReadyBootstrap> createState() => _LibReadyBootstrapState();
}

class _LibReadyBootstrapState extends State<LibReadyBootstrap> {
  SettingsRepository? _settings;
  LibraryRepository? _library;
  IdentityRepository? _identity;
  P2pService? _p2p;
  Object? _error;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final settings = await SettingsRepository.load();
      final library = LibraryRepository(settings: settings);
      final identity = await IdentityRepository.load();
      final p2p = P2pService(
        identity: identity.identity,
        storage: library.storage,
      );

      await library.init();
      unawaited(p2p.initialize());

      // Seed community store with books currently marked as shared in the local library
      for (final book in library.books) {
        if (book.isShared) {
          unawaited(p2p.advertiseBook(
            contentHash: book.contentHash,
            title: book.title,
            author: book.author,
            format: book.format.name.toLowerCase(),
            fileSize: book.fileSize,
          ));
        }
      }

      await pdfrxFlutterInitialize();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _library = library;
        _identity = identity;
        _p2p = p2p;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint('LibReady failed to start: $error\n$stack');
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_boot());
  }

  void _finishSplash() {
    if (!mounted) return;
    setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final library = _library;
    final identity = _identity;
    final p2p = _p2p;

    if (settings != null &&
        library != null &&
        identity != null &&
        p2p != null &&
        _splashDone) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider<LibraryRepository>.value(value: library),
          ChangeNotifierProvider<IdentityRepository>.value(value: identity),
          ChangeNotifierProvider<P2pService>.value(value: p2p),
        ],
        child: LibReadyApp(identity: identity),
      );
    }

    return MaterialApp(
      title: 'LibReady',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: BootSplash(
        ready: settings != null &&
            library != null &&
            identity != null &&
            p2p != null,
        error: _error,
        onRetry: _error == null ? null : _retry,
        onFinished: _finishSplash,
      ),
    );
  }
}

/// The animated first screen: three books rise onto a shelf while the name
/// settles into place, then the whole scene gently breathes until the app is
/// ready and fades into the library.
class BootSplash extends StatefulWidget {
  const BootSplash({
    super.key,
    required this.ready,
    required this.onFinished,
    this.error,
    this.onRetry,
  });

  /// True once preferences and the database are loaded.
  final bool ready;
  final Object? error;
  final VoidCallback? onRetry;

  /// Called after the exit fade, at which point the real app can be shown.
  final VoidCallback onFinished;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> with TickerProviderStateMixin {
  static const Duration _introDuration = Duration(milliseconds: 1650);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introDuration,
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
  );

  bool _introFinished = false;
  bool _exitStarted = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _introFinished = true;
        _maybeExit();
      }
    });
    _intro.forward();
    _ambient.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BootSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _maybeExit();
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _maybeExit() {
    if (_exitStarted || !widget.ready || !_introFinished) return;
    _exitStarted = true;
    // Let the entrance breathe for a moment before dissolving into the app.
    Future<void>.delayed(const Duration(milliseconds: 320), () async {
      if (!mounted) return;
      await _exit.forward();
      if (mounted) widget.onFinished();
    });
  }

  double _phase(double begin, double end) {
    return Interval(begin, end).transform(_intro.value).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _ambient, _exit]),
      builder: (context, _) {
        final exitValue = Curves.easeInCubic.transform(_exit.value);
        final float = math.sin(_ambient.value * math.pi * 2) * 3.0;

        return Scaffold(
          backgroundColor: AppColors.leatherDeep,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 1.05,
                colors: [Color(0xFF4A2E16), Color(0xFF2B1A0E), Color(0xFF16100A)],
                stops: [0, 0.55, 1],
              ),
            ),
            child: SafeArea(
              child: Opacity(
                opacity: 1 - exitValue,
                child: Transform.scale(
                  scale: 1 + exitValue * 0.03,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _logo(float),
                          const SizedBox(height: 30),
                          _name(),
                          const SizedBox(height: 12),
                          _rule(),
                          const SizedBox(height: 14),
                          _tagline(),
                          const SizedBox(height: 30),
                          _status(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _logo(double float) {
    final glow = Curves.easeOut.transform(_phase(0.0, 0.45));

    return SizedBox(
      height: 172,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Warm halo behind the shelf.
          Positioned(
            bottom: 20,
            child: Opacity(
              opacity: glow * 0.55,
              child: Container(
                width: 230,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(70),
                  gradient: RadialGradient(
                    colors: [
                      AppColors.brass.withValues(alpha: 0.30),
                      AppColors.brass.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, float),
            child: SizedBox(
              width: 186,
              height: 156,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  _book(
                    start: 0.16,
                    end: 0.52,
                    width: 34,
                    height: 86,
                    left: 24,
                    colors: const [Color(0xFF8A4746), Color(0xFF58292B)],
                    accent: const Color(0xFFD9A98D),
                  ),
                  _book(
                    start: 0.26,
                    end: 0.66,
                    width: 46,
                    height: 122,
                    left: 70,
                    colors: const [Color(0xFF7A5230), Color(0xFF3F2712)],
                    accent: AppColors.brass,
                    ribbon: true,
                  ),
                  _book(
                    start: 0.20,
                    end: 0.58,
                    width: 34,
                    height: 96,
                    left: 128,
                    colors: const [Color(0xFF35777D), Color(0xFF1C484E)],
                    accent: const Color(0xFF97CBCB),
                  ),
                  _shelf(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _book({
    required double start,
    required double end,
    required double width,
    required double height,
    required double left,
    required List<Color> colors,
    required Color accent,
    bool ribbon = false,
  }) {
    final t = _phase(start, end);
    final eased = Curves.easeOutBack.transform(t);
    final opacity = Curves.easeOut.transform(
      Interval(start, math.min(start + 0.2, end)).transform(_intro.value).clamp(
        0.0,
        1.0,
      ),
    );

    return Positioned(
      left: left,
      bottom: 12,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, (1 - eased) * 46),
          child: Transform.rotate(
            angle: (1 - t) * (left < 60 ? -0.12 : 0.10),
            alignment: Alignment.bottomCenter,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                  bottomLeft: Radius.circular(1.5),
                  bottomRight: Radius.circular(1.5),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: colors,
                ),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.35),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 9,
                    offset: const Offset(2, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Spine highlight.
                  Positioned(
                    left: 3,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1.2,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  if (ribbon)
                    Positioned(
                      top: 0,
                      left: width * 0.5 - 3,
                      child: Container(
                        width: 6,
                        height: height * 0.34,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: height * (ribbon ? 0.25 : 0.32),
                    child: Column(
                      children: [
                        for (var i = 0; i < (ribbon ? 4 : 3); i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Container(
                              height: 1.4,
                              width: i == 0 ? width * 0.42 : width * 0.62,
                              color: accent.withValues(alpha: 0.65),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shelf() {
    final t = Curves.easeOut.transform(_phase(0.0, 0.32));
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scaleX: 0.6 + 0.4 * t,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF9A6738), Color(0xFF4B2F18)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _name() {
    final t = Curves.easeOutCubic.transform(_phase(0.42, 0.82));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 14),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            // A brass sheen that drifts slowly across the wordmark.
            final drift = _ambient.value;
            return LinearGradient(
              begin: Alignment(-1.6 + drift * 0.5, 0),
              end: Alignment(1.6 + drift * 0.5, 0),
              colors: const [
                Color(0xFFF3E8D2),
                Color(0xFFE3C08A),
                Color(0xFFFFF6E6),
                Color(0xFFC39A5F),
              ],
              stops: const [0.0, 0.35, 0.62, 1.0],
            ).createShader(bounds);
          },
          child: Text(
            'LibReady',
            textAlign: TextAlign.center,
            style: serifStyle(
              fontSize: 44,
              fontWeight: FontWeight.w600,
              letterSpacing: 10.0 - 8.2 * t,
              color: Colors.white,
            ).copyWith(
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rule() {
    final t = Curves.easeOutCubic.transform(_phase(0.6, 0.92));
    return Container(
      width: 158 * t,
      height: 1.1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brass.withValues(alpha: 0),
            AppColors.brass.withValues(alpha: 0.9),
            AppColors.brass.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }

  Widget _tagline() {
    final t = Curves.easeOut.transform(_phase(0.7, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 8),
        child: const Text(
          'YOUR PRIVATE, OFFLINE LIBRARY',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 3.1,
            fontWeight: FontWeight.w500,
            color: Color(0xFFD9C6A6),
          ),
        ),
      ),
    );
  }

  Widget _status() {
    final showProgress = _introFinished && !widget.ready && widget.error == null;
    final showError = widget.error != null;

    return SizedBox(
      height: 58,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: showError
            ? _errorBlock()
            : showProgress
            ? _loadingBlock()
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _loadingBlock() {
    return Column(
      key: const ValueKey<String>('loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 132,
          height: 1.6,
          child: LinearProgressIndicator(
            minHeight: 1.6,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.brass.withValues(alpha: 0.85),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Opening your library…',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.4,
            color: Color(0xFFB9A283),
          ),
        ),
      ],
    );
  }

  Widget _errorBlock() {
    return Column(
      key: const ValueKey<String>('error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LibReady could not start.',
          style: TextStyle(
            fontSize: 12.5,
            color: const Color(0xFFE7C4B8).withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onRetry,
          child: const Text('Try again'),
        ),
      ],
    );
  }
}
