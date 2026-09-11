import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// تحريك شريط أفقي ببطء، مع إعطاء الأولوية للتصفح اليدوي دائماً.
class SlowAutoScroll extends StatefulWidget {
  const SlowAutoScroll({super.key, required this.builder, this.enabled = true});

  final Widget Function(BuildContext, ScrollController) builder;
  final bool enabled;

  @override
  State<SlowAutoScroll> createState() => _SlowAutoScrollState();
}

class _SlowAutoScrollState extends State<SlowAutoScroll>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _pixelsPerSecond = 12.0;
  static const _extentTolerance = .1;

  late final ScrollController _controller;
  late final Ticker _ticker;
  ScrollPosition? _verticalPosition;
  ModalRoute<dynamic>? _route;
  Duration _lastElapsed = Duration.zero;
  double _direction = 1;
  double _viewportHeight = 0;
  bool _appVisible = true;
  bool _tickerEnabled = true;
  bool _reducedMotion = false;
  bool _visible = false;
  bool _checkScheduled = false;
  bool _drivingScroll = false;
  bool _manualScrolling = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appVisible =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    _controller = ScrollController(
      onAttach: (_) => _scheduleCheck(),
      onDetach: (_) => _stopTicker(),
    );
    _controller.addListener(_positionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _viewportHeight = MediaQuery.sizeOf(context).height;
    // الاعتماد على المسار يعيد الفحص عند فتح صفحة أو نافذة فوق الرئيسية.
    _route = ModalRoute.of(context);
    final vertical = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (_verticalPosition != vertical) {
      _verticalPosition?.removeListener(_scheduleCheck);
      _verticalPosition = vertical;
      _verticalPosition?.addListener(_scheduleCheck);
    }
    _updateMotion();
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(covariant SlowAutoScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
    _scheduleCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // النافذة المرئية قد تفقد التركيز؛ يواصل Flutter الرسم في حالة inactive.
    _appVisible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _updateMotion();
    if (_appVisible) _scheduleCheck();
  }

  void _positionChanged() {
    if (!_drivingScroll) _scheduleCheck();
  }

  void _scheduleCheck() {
    if (!mounted || _checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      _visible = false;
      if (box is RenderBox && box.attached && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        // العمود قد يكون وسط نافذة عريضة؛ موضعه الأفقي لا يحدد ظهوره.
        _visible =
            top.isFinite && top < _viewportHeight && top + box.size.height > 0;
      }
      _updateMotion();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _canMove {
    if (!mounted ||
        !widget.enabled ||
        !_appVisible ||
        !_tickerEnabled ||
        _reducedMotion ||
        !_visible ||
        _route?.isCurrent == false ||
        _manualScrolling ||
        _controller.positions.length != 1) {
      return false;
    }
    final position = _controller.position;
    return position.hasContentDimensions &&
        position.minScrollExtent.isFinite &&
        position.maxScrollExtent.isFinite &&
        position.maxScrollExtent - position.minScrollExtent > _extentTolerance;
  }

  void _updateMotion() {
    if (!_canMove) {
      _stopTicker();
    } else if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _stopTicker() {
    if (_ticker.isActive) _ticker.stop();
    _lastElapsed = Duration.zero;
  }

  void _tick(Duration elapsed) {
    if (!_canMove) {
      _stopTicker();
      return;
    }
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    // لا نقفز مسافة كبيرة بعد تجمّد إطار أو خفض المتصفح لمعدل الرسم.
    final seconds = math.min(delta.inMicroseconds / 1000000, .1);
    if (seconds <= 0) return;
    final position = _controller.position;
    final target = (position.pixels + _direction * _pixelsPerSecond * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _drivingScroll = true;
    try {
      _controller.jumpTo(target);
    } finally {
      _drivingScroll = false;
    }
    final reachedEdge = _direction > 0
        ? target >= position.maxScrollExtent
        : target <= position.minScrollExtent;
    if (reachedEdge) {
      // ينعكس الاتجاه مباشرة حتى تبقى الحركة متصلة عند طرف القائمة.
      _direction = -_direction;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (_drivingScroll ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _manualScrolling = true;
      _updateMotion();
    } else if (notification is ScrollEndNotification) {
      _manualScrolling = false;
      _updateMotion();
    }
    // تبقى إشعارات التمرير متاحة للصفحة ولمؤشرات التمرير الأصلية.
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verticalPosition?.removeListener(_scheduleCheck);
    _ticker.dispose();
    _controller.removeListener(_positionChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.horizontal) {
            _scheduleCheck();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.builder(context, _controller),
        ),
      );
}
