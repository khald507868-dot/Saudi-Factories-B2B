import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/video_promotion_service.dart';
import 'common.dart';

/// نحمّل أغلفة البطاقات فقط؛ يبدأ تحميل المقطع عندما يطلب الزائر تشغيله.
class HomeVideoPromotions extends StatelessWidget {
  const HomeVideoPromotions({
    super.key,
    required this.promotions,
    required this.onRetry,
    this.onManage,
    this.onOpen,
  });

  final Future<List<SFVideoPromotion>> promotions;
  final VoidCallback onRetry;
  final VoidCallback? onManage;
  final ValueChanged<SFVideoPromotion>? onOpen;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SFVideoPromotion>>(
    future: promotions,
    builder: (context, snapshot) {
      final items = (snapshot.data ?? const <SFVideoPromotion>[])
          .where((ad) => ad.isActive)
          .toList();
      if (items.isEmpty && onManage == null) return const SizedBox.shrink();
      return Padding(
        key: const ValueKey('home-video-ads'),
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('video_ads_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onManage != null)
                    IconButton(
                      onPressed: onManage,
                      tooltip: context.t('video_ads_admin_title'),
                      icon: const Icon(Icons.video_settings_outlined),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (items.isNotEmpty)
              SizedBox(
                height:
                    276 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 2,
                child: ListView.separated(
                  key: const PageStorageKey('video-ad-strip'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final ad = items[index];
                    return VideoAdCard(
                      ad: ad,
                      onTap: () {
                        if (onOpen != null) {
                          onOpen!(ad);
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VideoAdPlayer(ad: ad),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              )
            else if (snapshot.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              )
            else if (snapshot.hasError)
              SFStateView(
                message: context.t('video_ads_unavailable'),
                onRetry: onRetry,
                icon: Icons.cloud_off_outlined,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(context.t('video_ads_add')),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class VideoAdCard extends StatelessWidget {
  const VideoAdCard({super.key, required this.ad, required this.onTap});
  final SFVideoPromotion ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 152,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '${context.t('video_ads_play')}: ${ad.title}',
              button: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 152,
                  height: 228,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SFImage(
                        url: ad.imageUrl,
                        width: 152,
                        height: 228,
                        fit: BoxFit.cover,
                        placeholderIcon: Icons.video_library_outlined,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x33000000),
                              Colors.transparent,
                              Color(0x55000000),
                            ],
                            stops: [0, .55, 1],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x77000000),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              context.t('video_ads_badge'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (ad.logoUrl.isNotEmpty)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Container(
                            width: 38,
                            height: 38,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SFImage(
                                url: ad.logoUrl,
                                width: 34,
                                height: 34,
                              ),
                            ),
                          ),
                        ),
                      const PositionedDirectional(
                        bottom: 12,
                        end: 12,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ad.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// مشغّل مستقل لا يواصل الصوت بعد إغلاقه أو انتقال التطبيق إلى الخلفية.
class VideoAdPlayer extends StatefulWidget {
  const VideoAdPlayer({super.key, required this.ad});
  final SFVideoPromotion ad;
  @override
  State<VideoAdPlayer> createState() => _VideoAdPlayerState();
}

class _VideoAdPlayerState extends State<VideoAdPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _openingLink = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final old = _controller;
    _controller = null;
    old?.removeListener(_changed);
    setState(() => _failed = false);
    try {
      await old?.dispose();
      if (!mounted) return;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.ad.videoUrl),
      );
      _controller = controller;
      controller.addListener(_changed);
      await controller.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || _controller != controller) return;
      await controller.setLooping(true);
      // الكتم يسمح بتشغيل الفيديو على متصفحات تمنع التشغيل التلقائي بالصوت.
      await controller.setVolume(0);
      if (!mounted || _controller != controller) return;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openLink() async {
    if (_openingLink) return;
    final value = widget.ad.targetUrl;
    if (value.isEmpty || !SFVideoPromotion.isValidTargetUrl(value)) return;
    setState(() => _openingLink = true);
    await _controller?.pause();
    try {
      final opened = await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        showSFMessage(context, context.t('promo_target_invalid'));
      }
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _openingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller?.value.isInitialized == true;
    final failed = _failed || controller?.value.hasError == true;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.ad.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: context.t('video_ads_close'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_outlined,
                            color: Colors.white70,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.t('video_ads_failed'),
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: Text(
                              context.t('app_retry'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    : !ready
                    ? const CircularProgressIndicator(color: Colors.white)
                    : AspectRatio(
                        aspectRatio: controller!.value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
              ),
            ),
            if (ready && !failed) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VideoProgressIndicator(
                  controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: SFColors.green,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    color: Colors.white,
                    tooltip: context.t(
                      controller.value.isPlaying
                          ? 'video_ads_pause'
                          : 'video_ads_play',
                    ),
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    onPressed: () => controller.value.isPlaying
                        ? controller.pause()
                        : controller.play(),
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: context.t(
                      controller.value.volume == 0
                          ? 'video_ads_unmute'
                          : 'video_ads_mute',
                    ),
                    icon: Icon(
                      controller.value.volume == 0
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                    ),
                    onPressed: () => controller.setVolume(
                      controller.value.volume == 0 ? 1 : 0,
                    ),
                  ),
                ],
              ),
            ],
            if (widget.ad.targetUrl.isNotEmpty &&
                SFVideoPromotion.isValidTargetUrl(widget.ad.targetUrl))
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _openingLink ? null : _openLink,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.t('video_ads_open')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
