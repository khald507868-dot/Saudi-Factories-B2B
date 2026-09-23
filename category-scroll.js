/* One continuous category strip for the homepage and shared catalog header. */
(function (root) {
  'use strict';
  function mount(box) {
    if (!box || !root.SFBestsellersScroll) return;
    if (box.sfStopCategoryScroll) box.sfStopCategoryScroll();
    var area = box.closest('.dt-catbar-inner') || box;
    var left = document.getElementById('dt-catnav-left');
    var right = document.getElementById('dt-catnav-right');
    var disposers = [], timers = new Set();
    function listen(target, event, handler, options) {
      target.addEventListener(event, handler, options);
      disposers.push(function () { target.removeEventListener(event, handler, options); });
    }
    // Frame-driven scrolling must not restart a CSS smooth transition on each frame.
    var previousBehavior = box.style.scrollBehavior;
    box.style.scrollBehavior = 'auto';
    root.SFBestsellersScroll.mount(box, {
      itemSelector: 'a', sectionSelector: '.dt-catbar', copyClass: 'dt-category-copy',
      speed: 80, hoverTarget: area,
      isPaused: function () { return area.contains(document.activeElement); }
    });
    function sync() {
      var scrollable = box.scrollWidth > box.clientWidth + 1;
      [left, right].forEach(function (button) {
        if (!button) return;
        button.classList.toggle('is-active', scrollable);
        button.disabled = !scrollable;
      });
    }
    function stopHolds() {
      timers.forEach(function (timer) { clearInterval(timer); }); timers.clear();
    }
    [left, right].forEach(function (button, index) {
      if (!button) return;
      var timer = null, direction = index === 0 ? -1 : 1;
      function stop() { if (timer !== null) { clearInterval(timer); timers.delete(timer); timer = null; } }
      listen(button, 'mouseenter', function () {
        stop();
        timer = setInterval(function () { box.scrollLeft += direction * 4; }, 20);
        timers.add(timer);
      });
      listen(button, 'mouseleave', stop);
      listen(button, 'click', function () {
        box.scrollBy({left: direction * 240, behavior: 'smooth'});
      });
    });
    listen(area, 'mouseleave', stopHolds);
    listen(root, 'blur', stopHolds);
    listen(root, 'pagehide', stopHolds);
    listen(document, 'visibilitychange', function () { if (document.hidden) stopHolds(); });
    listen(box, 'wheel', function (event) {
      if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
      event.preventDefault();
      var sign = getComputedStyle(box).direction === 'rtl' ? -1 : 1;
      var scale = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? box.clientWidth : 1;
      box.scrollLeft += sign * event.deltaY * scale;
    }, {passive: false});
    listen(box, 'scroll', sync, {passive: true});
    var size = new ResizeObserver(sync); size.observe(box); sync();
    box.sfStopCategoryScroll = function () {
      stopHolds(); size.disconnect();
      disposers.forEach(function (dispose) { dispose(); });
      if (box.sfStopScroll) box.sfStopScroll();
      box.style.scrollBehavior = previousBehavior;
      delete box.sfStopCategoryScroll;
    };
  }
  root.SFCategoryScroll = {mount: mount};
})(window);
