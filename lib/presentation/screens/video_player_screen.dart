import 'package:flutter/material.dart';
import 'package:riyo/core/video_engine/riyo_video_engine.dart';
import 'package:riyo/core/video_engine/texture_bridge.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:riyo/providers/auth_provider.dart';
import 'package:riyo/services/api_service.dart';
import 'package:riyo/models/movie.dart';
import 'package:riyo/core/casting/presentation/widgets/cast_button.dart';
import 'package:riyo/core/casting/presentation/providers/casting_provider.dart';
import 'package:riyo/core/casting/domain/entities/cast_media.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:webview_flutter/webview_flutter.dart';

class VideoPlayerScreen extends rp.ConsumerStatefulWidget {
  final String? movieId;
  final String? videoUrl;
  final int? season;
  final int? episode;

  const VideoPlayerScreen({super.key, this.movieId, this.videoUrl, this.season, this.episode});

  @override
  rp.ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends rp.ConsumerState<VideoPlayerScreen> {
  RiyoVideoEngine? _engine;
  int? _textureId;
  WebViewController? _webController;
  bool _isControlsVisible = true;
  Timer? _hideControlsTimer;
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  double _playbackSpeed = 1.0;
  String _selectedQuality = 'Auto';
  String _selectedAudio = 'English';
  String _selectedSubtitle = 'Off';

  Movie? _movie;
  List<StreamSource> _sources = [];
  StreamSource? _selectedSource;
  int _currentSourceIndex = 0;
  bool _isError = false;
  bool _isLoadingSource = true;

  // Real-time tracking
  double _position = 0;
  double _duration = 1;
  double _bufferPosition = 0;
  Timer? _playbackTimer;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _fetchData();
    _initVolume();
    _initBrightness();
    _initCastListener();
    _startPlaybackTimer();
  }

  void _startPlaybackTimer() {
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_engine != null && _engine!.getState() == 2) {
         setState(() {
           // These values would normally come from the native engine
           _position = _engine!.getPosition();
           _duration = _engine!.getDuration();
           if (_duration <= 0) _duration = 1;
         });
      }
    });
  }

  Future<void> _fetchData() async {
    final apiService = ApiService();
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (widget.movieId != null) {
      try {
        _movie = await apiService.getMovieDetails(widget.movieId!, token: auth.token);
        final response = await apiService.getSources(widget.movieId!, season: widget.season, episode: widget.episode);

        final List<dynamic> sourceData = response['sources'] ?? [];
        _sources = sourceData.map((s) => StreamSource.fromJson(s)).toList();

        // 5. SOURCE HANDLING - Implement Source priority system
        // Priority order: 1. Direct MP4 (direct), 2. M3U8 HLS (hls), 3. DASH (dash), 4. Embed (embed)
        // Also sort by quality if type is same
        _sources.sort((a, b) {
          int typeScore(String type) {
            if (type == 'direct') return 4;
            if (type == 'hls') return 3;
            if (type == 'dash') return 2;
            if (type == 'embed') return 1;
            return 0;
          }
          int qualityScore(String q) {
            final lowerQ = q.toLowerCase();
            if (lowerQ.contains('4k')) return 4;
            if (lowerQ.contains('1080')) return 3;
            if (lowerQ.contains('720')) return 2;
            if (lowerQ.contains('480')) return 1;
            return 0;
          }

          final ts = typeScore(b.type).compareTo(typeScore(a.type));
          if (ts != 0) return ts;
          return qualityScore(b.quality).compareTo(qualityScore(a.quality));
        });

        if (_sources.isNotEmpty) {
          _currentSourceIndex = 0;
          _selectedSource = _sources[_currentSourceIndex];
          if (mounted) _initPlayer();
        } else if (widget.videoUrl != null) {
          if (mounted) _initPlayer();
        } else {
          if (mounted) {
            setState(() {
              _isError = true;
              _isLoadingSource = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching player data: $e');
        if (mounted) {
          setState(() {
            _isError = true;
            _isLoadingSource = false;
          });
        }
      }
    } else if (widget.videoUrl != null) {
      if (mounted) _initPlayer();
    } else {
      if (mounted) {
        setState(() {
          _isError = true;
          _isLoadingSource = false;
        });
      }
    }
  }

  void _initCastListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(castingProvider, (previous, next) {
        if (next.connectedDevice != null && _engine != null && _engine!.getState() == 2) {
           _startCasting();
        }
      });
    });
  }

  Future<void> _startCasting() async {
    final castingNotifier = ref.read(castingProvider.notifier);
    String? url = _selectedSource?.url ?? widget.videoUrl;
    String? title = _movie?.title ?? "Video";
    String? poster = _movie != null ? (_movie!.posterPath.startsWith('http') ? _movie!.posterPath : 'https://image.tmdb.org/t/p/w500${_movie!.posterPath}') : null;

    if (url != null) {
      _engine?.pause();
      await castingNotifier.castMedia(CastMedia(
        url: url,
        title: title,
        posterUrl: poster,
      ));
    }
  }

  Future<void> _initPlayer() async {
    setState(() => _isLoadingSource = true);

    String? url = _selectedSource?.url ?? widget.videoUrl;
    if (url == null) {
      setState(() => _isLoadingSource = false);
      return;
    }

    if (_selectedSource?.type == 'embed') {
      _engine?.dispose();
      _engine = null;
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..loadRequest(Uri.parse(url));
      if (mounted) {
        setState(() => _isLoadingSource = false);
      }
      return;
    }

    _engine?.dispose();
    _engine = RiyoVideoEngine();
    _textureId = await TextureRegistryBridge.createTexture();

    // 2. IMPROVE THE VIDEO PLAYER - Integrate ExoPlayer (via native engine)
    _engine!.load(url);
    _engine!.setEventCallback();

    // 6. ERROR HANDLING - Improve reliability of streaming
    // Automatic switch to another source if one fails
    _eventSubscription?.cancel();
    _eventSubscription = _engine!.eventStream.listen((event) {
      if (event['event'] == 3) { // Assume 3 is ERROR event from native engine
        debugPrint('Native player error received, switching source...');
        _handleSourceError();
      }
    });

    _engine!.play();

    if (mounted) {
      setState(() => _isLoadingSource = false);
      _startHideControlsTimer();
    }
  }

  void _handleSourceError() {
    if (_currentSourceIndex + 1 < _sources.length) {
      _currentSourceIndex++;
      _selectedSource = _sources[_currentSourceIndex];
      debugPrint('Switching to next source: ${_selectedSource?.label}');
      _initPlayer();
    } else {
      setState(() {
        _isError = true;
        _isLoadingSource = false;
      });
    }
  }

  Future<void> _initVolume() async {
    _currentVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    if (mounted) setState(() {});
  }

  Future<void> _initBrightness() async {
    try {
      _currentBrightness = await ScreenBrightness().application;
    } catch (e) {
      _currentBrightness = 0.5;
    }
    if (mounted) setState(() {});
  }

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
    if (_isControlsVisible) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _engine != null && _engine!.getState() == 2) {
        setState(() {
          _isControlsVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _eventSubscription?.cancel();
    WakelockPlus.disable();
    _engine?.dispose();
    if (_textureId != null) {
      TextureRegistryBridge.releaseTexture(_textureId!);
    }
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _seekRelative(Duration duration) {
    if (_engine == null) return;
    final target = (_position + duration.inSeconds).clamp(0, _duration);
    _engine!.seek(target.toDouble());
    _startHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text('All streaming sources failed.', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: <Widget>[
            Center(
              child: _selectedSource?.type == 'embed'
                  ? (_webController != null
                      ? WebViewWidget(controller: _webController!)
                      : const CircularProgressIndicator(color: Colors.purple))
                  : (_textureId != null)
                      ? Texture(textureId: _textureId!)
                      : const CircularProgressIndicator(color: Colors.purple),
            ),
            if (_isLoadingSource)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.purple),
                      SizedBox(height: 16),
                      Text('Finding best stream...', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            if (_isControlsVisible) _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent, Colors.black.withOpacity(0.7)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(),
            if (_selectedSource?.type != 'embed') _buildPlaybackControls(),
            const Spacer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _movie?.title ?? 'Loading...',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.season != null)
                   Text('Season ${widget.season} • Episode ${widget.episode}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const CastingButton(),
          // Button to trigger manual fallback/source switch
          IconButton(
            icon: const Icon(Icons.shuffle_rounded, color: Colors.white),
            tooltip: 'Try Another Source',
            onPressed: _handleSourceError,
          ),
          IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => _showSettingsMenu()),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls() {
    if (_engine == null) return const SizedBox();
    final isPlaying = _engine!.getState() == 2;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 48),
          onPressed: () => _seekRelative(const Duration(seconds: -10)),
        ),
        const SizedBox(width: 48),
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
            color: Colors.purple,
            size: 96,
          ),
          onPressed: () {
            setState(() {
              isPlaying ? _engine!.pause() : _engine!.play();
              _startHideControlsTimer();
            });
          },
        ),
        const SizedBox(width: 48),
        IconButton(
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 48),
          onPressed: () => _seekRelative(const Duration(seconds: 10)),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          if (_selectedSource?.type != 'embed')
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                   SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.purple,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _position,
                      max: _duration,
                      onChanged: (val) {
                        setState(() => _position = val);
                        _engine!.seek(val);
                      },
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedSource?.type == 'embed' ? 'EXTERNAL SERVER' : '${_formatDuration(Duration(seconds: _position.toInt()))} / ${_formatDuration(Duration(seconds: _duration.toInt()))}',
                style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              Row(
                children: [
                  _buildControlItem(Icons.dns_rounded, _selectedSource?.label ?? 'SERVER', _showSourceMenu),
                  if (_selectedSource?.type != 'embed')
                    _buildControlItem(Icons.speed_rounded, '${_playbackSpeed}x', _showSpeedMenu),
                  _buildControlItem(Icons.high_quality_rounded, _selectedSource?.quality ?? _selectedQuality, _showQualityMenu),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds";
  }

  Widget _buildControlItem(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 8, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  void _showSourceMenu() {
    _showBottomDialog('SELECT SERVER', _sources.map((s) => '${s.label} (${s.quality})').toList(), (val) {
      final index = _sources.indexWhere((s) => '${s.label} (${s.quality})' == val);
      setState(() {
        _currentSourceIndex = index;
        _selectedSource = _sources[index];
        _initPlayer();
      });
    });
  }

  void _showSpeedMenu() {
    _showBottomDialog('PLAYBACK SPEED', ['0.5x', '1.0x', '1.5x', '2.0x'], (val) {
      setState(() {
        _playbackSpeed = double.parse(val.replaceAll('x', ''));
      });
    });
  }

  void _showQualityMenu() {
    _showBottomDialog('VIDEO QUALITY', ['AUTO', '720P', '1080P', '4K'], (val) {
      setState(() => _selectedQuality = val);
    });
  }

  void _showSettingsMenu() {
    _showBottomDialog('PLAYER SETTINGS', ['AUTO-PLAY NEXT', 'SKIP INTRO', 'SKIP CREDITS'], (val) {});
  }

  void _showBottomDialog(String title, List<String> options, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            const SizedBox(height: 24),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (c, i) => Divider(color: Theme.of(context).dividerColor),
                itemBuilder: (context, index) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(options[index], style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () {
                    onSelect(options[index]);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
