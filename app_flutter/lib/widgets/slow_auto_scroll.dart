import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// شريط دائري بطيء. يبني المستدعي نسخاً متطابقة عند الحاجة للتمرير.
class SlowAutoScroll extends StatefulWidget {
  const SlowAutoScroll({
    super.key,
    required this.builder,
    required this.cycleExtent,
    required this.contentExtent,
    this.enabled = true,
  }) : assert(cycleExtent > 0),
       assert(contentExtent >= 0);

  final Widget Function(BuildContext, ScrollController, int repetitions)
  builder;
  // طول النسخة شاملاً الفاصل بين آخر عنصر وأول عنصر في النسخة التالية.
  final double cycleExtent;
  // عرض نسخة واحدة مع الهوامش، لتجنب تكرار قائمة تتسع بالكامل للشاشة.
  final double contentExtent;
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
  double _viewportHeight = 0;
  bool _looping = false;
  bool _resetPosition = true;
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
      keepScrollOffset: false,
      onAttach: (_) {
        _resetPosition = true;
        _scheduleCheck();
      },
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
    if (oldWidget.cycleExtent != widget.cycleExtent) _resetPosition = true;
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
      if (_controller.positions.length == 1 &&
          _controller.position.hasContentDimensions &&
          !_manualScrolling) {
        if (_resetPosition) {
          _resetPosition = false;
          _jumpTo(_looping ? widget.cycleExtent : 0);
        } else if (_looping) {
          final current = _controller.position.pixels;
          final normalized = _loopOffset(current);
          if ((current - normalized).abs() > _extentTolerance) {
            _jumpTo(normalized);
          }
        }
      }
      _updateMotion();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _canMove {
    if (!mounted ||
        !widget.enabled ||
        !_looping ||
        _resetPosition ||
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
    _jumpTo(
      _loopOffset(_controller.position.pixels + _pixelsPerSecond * seconds),
    );
  }

  double _loopOffset(double offset) =>
      widget.cycleExtent + (offset - widget.cycleExtent) % widget.cycleExtent;

  void _jumpTo(double offset) {
    final position = _controller.position;
    final target = offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _drivingScroll = true;
    try {
      _controller.jumpTo(target);
    } finally {
      _drivingScroll = false;
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
      _scheduleCheck();
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final looping =
          constraints.hasBoundedWidth &&
          widget.contentExtent > constraints.maxWidth + _extentTolerance;
      if (_looping != looping) {
        _looping = looping;
        _resetPosition = true;
        _scheduleCheck();
      }
      // تكفي ثلاث نسخ عادةً؛ نسخة إضافية تمنع ظهور هامش النهاية إذا كان
      // عرض الشاشة أكبر بقليل من الدورة وكانت الهوامش سبب التجاوز.
      final repetitions = _looping
          ? math.max(3, (constraints.maxWidth / widget.cycleExtent).ceil() + 2)
          : 1;
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.horizontal) {
            _scheduleCheck();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: widget.builder(context, _controller, repetitions),
          ),
        ),
      );
    },
  );
}
