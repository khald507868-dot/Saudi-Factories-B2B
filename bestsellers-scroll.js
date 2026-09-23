/* Continuous catalogue scrolling; cards keep their existing links and actions. */
(function (global) {
  'use strict';

  function mount(view, options) {
    options = options || {};
    if (view.sfStopScroll) view.sfStopScroll();
    var originals = Array.from(view.querySelectorAll(options.itemSelector || '.product-cell'));
    if (!originals.length) return;
    var section = view.closest(options.sectionSelector || '.bestsellers-section');
    var control = section.querySelector(options.controlSelector || '.bestsellers-pause');
    var motion = global.matchMedia('(prefers-reduced-motion: reduce)');
    var speed = Number.isFinite(options.speed) && options.speed > 0 ? options.speed : 26;
    var hoverTarget = options.hoverTarget || view;
    var paused = motion.matches;
    var hover = false, touching = false, visible = true;
    var last = 0, frame = 0, span = 0, position = 0, looping = false;
    var sign = getComputedStyle(view).direction === 'rtl' ? -1 : 1;
    var manualUntil = 0;
    var disposers = [];
    var clones = [];
    var fillClones = [];

    function listen(target, event, handler, options) {
      target.addEventListener(event, handler, options);
      disposers.push(function () { target.removeEventListener(event, handler, options); });
    }
    function copy(card) {
      var clone = card.cloneNode(true);
      clone.classList.add(options.copyClass || 'bestsellers-copy');
      clone.setAttribute('aria-hidden', 'true');
      if (clone.matches('a,button,[tabindex]')) clone.tabIndex = -1;
      clone.querySelectorAll('a,button,[tabindex]').forEach(function (el) { el.tabIndex = -1; });
      clones.push(clone);
      return clone;
    }
    // A copy on each side allows wrapping in either scroll direction.
    var before = document.createDocumentFragment();
    originals.forEach(function (card) { before.appendChild(copy(card)); });
    view.insertBefore(before, originals[0]);
    originals.forEach(function (card) { view.appendChild(copy(card)); });

    function updateControl() {
      if (!control) return;
      control.hidden = !looping;
      control.setAttribute('aria-label', I18N.t(paused ? 'video_ads_play' : 'video_ads_pause'));
      control.title = control.getAttribute('aria-label');
      control.setAttribute('aria-pressed', String(paused));
      control.innerHTML = paused
        ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 10 7-10 7z"/></svg>'
        : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5v14M15 5v14"/></svg>';
    }
    function measure() {
      var oldSpan = span, wasLooping = looping;
      var oldPosition = Math.abs(view.scrollLeft);
      sign = getComputedStyle(view).direction === 'rtl' ? -1 : 1;
      var gap = parseFloat(getComputedStyle(view).columnGap) || 0;
      span = originals.reduce(function (sum, card) { return sum + card.getBoundingClientRect().width + gap; }, 0);
      looping = originals.length > 1 && span > 0 && (options.repeatToFill || span - gap > view.clientWidth);
      // A short image gallery still moves without leaving blank space on wide screens.
      if (options.repeatToFill) {
        fillClones.forEach(function (card) { card.remove(); });
        clones = clones.filter(function (card) { return fillClones.indexOf(card) === -1; });
        fillClones = [];
        var extra = looping ? Math.max(0, Math.ceil(view.clientWidth / span) - 1) : 0;
        for (var i = 0; i < extra; i++) originals.forEach(function (card) {
          var clone = copy(card); fillClones.push(clone); view.appendChild(clone);
        });
      }
      clones.forEach(function (card) { card.hidden = !looping; });
      // Preserve the current point in the cycle when fonts or the viewport resize.
      position = looping ? span + (wasLooping && oldSpan > 0 ? (oldPosition % oldSpan) / oldSpan * span : 0) : 0;
      view.scrollLeft = sign * position;
      last = 0;
      updateControl();
    }
    function normalize() {
      if (!looping || view.contains(document.activeElement)) return;
      var current = sign * view.scrollLeft;
      if (current < span - 1 || current >= 2 * span) {
        position = span + ((current % span) + span) % span;
        view.scrollLeft = sign * position;
      }
    }
    function tick(now) {
      var elapsed = last ? Math.min((now - last) / 1000, .05) : 0;
      last = now;
      if (looping && visible && !document.hidden && !paused && !hover && !touching &&
          !(options.isPaused && options.isPaused()) &&
          !view.contains(document.activeElement) && now > manualUntil) {
        position += elapsed * speed;
        if (position >= span * 2) position -= span;
        view.scrollLeft = sign * position;
      }
      frame = requestAnimationFrame(tick);
    }
    if (options.pauseOnHover !== false) {
      listen(hoverTarget, 'mouseenter', function () { hover = true; });
      listen(hoverTarget, 'mouseleave', function () { hover = false; position = sign * view.scrollLeft; last = 0; });
    }
    listen(view, 'pointerdown', function () { touching = true; });
    listen(global, 'pointerup', function () { touching = false; manualUntil = performance.now() + 2500; });
    listen(global, 'pointercancel', function () { touching = false; });
    listen(view, 'wheel', function () { manualUntil = performance.now() + 2500; }, { passive: true });
    listen(view, 'scroll', function () {
      normalize();
      if (hover || touching || paused || performance.now() <= manualUntil || view.contains(document.activeElement) || (options.isPaused && options.isPaused())) {
        position = sign * view.scrollLeft;
      }
    }, { passive: true });
    listen(view, 'focusout', function () { position = sign * view.scrollLeft; });
    if (control) listen(control, 'click', function () { paused = !paused; updateControl(); });
    listen(motion, 'change', function () { paused = motion.matches; updateControl(); });
    listen(document, 'visibilitychange', function () { last = 0; });
    var size = new ResizeObserver(measure);
    size.observe(view);
    size.observe(originals[0]);
    var direction = new MutationObserver(measure);
    direction.observe(document.documentElement, { attributes: true, attributeFilter: ['dir'] });
    var visibility = new IntersectionObserver(function (entries) { visible = entries[0].isIntersecting; last = 0; });
    visibility.observe(view);
    measure();
    frame = requestAnimationFrame(tick);
    view.sfStopScroll = function () {
      cancelAnimationFrame(frame);
      size.disconnect();
      direction.disconnect();
      visibility.disconnect();
      disposers.forEach(function (dispose) { dispose(); });
      clones.forEach(function (card) { card.remove(); });
      if (control) control.hidden = true;
      delete view.sfStopScroll;
    };
  }

  global.SFBestsellersScroll = { mount: mount };
})(window);
