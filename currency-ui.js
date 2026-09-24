/* اختيار اللغة وعملة العرض في نافذة واحدة؛ لا تطبق المسودة إلا عند الحفظ. */
(function (root) {
  'use strict';
  var doc = root.document;
  if (!doc) return;
  var LANGUAGES = [
    ["العربية", "Arabic", "ar"],
    ["الإنجليزية", "English", "en"],
    ["الفرنسية", "Français", "fr"],
    ["الإسبانية", "Español", "es"],
    ["الألمانية", "Deutsch", "de"],
    ["الإيطالية", "Italiano", "it"],
    ["البرتغالية", "Português", "pt"],
    ["الهولندية", "Nederlands", "nl"],
    ["السويدية", "Svenska", "sv"],
    ["البولندية", "Polski", "pl"],
    ["اليونانية", "Ελληνικά", "el"],
    ["الروسية", "Русский", "ru"],
    ["التركية", "Türkçe", "tr"],
    ["الفارسية", "فارسی", "fa"],
    ["الأردية", "اردو", "ur"],
    ["الهندية", "हिन्दी", "hi"],
    ["البنغالية", "বাংলা", "bn"],
    ["البنجابية", "ਪੰਜਾਬੀ", "pa"],
    ["التاميلية", "தமிழ்", "ta"],
    ["التايلاندية", "ไทย", "th"],
    ["الفيتنامية", "Tiếng Việt", "vi"],
    ["الإندونيسية", "Bahasa Indonesia", "id"],
    ["الماليزية", "Bahasa Melayu", "ms"],
    ["الصينية (المبسطة)", "中文 (简体)", "zh"],
    ["اليابانية", "日本語", "ja"],
    ["الكورية", "한국어", "ko"],
    ["العبرية", "עברית", "he"],
    ["الكردية", "Kurdî", "ku"],
    ["الأمهرية", "አማርኛ", "am"],
    ["السواحيلية", "Kiswahili", "sw"]
  ];
  var button, panel, language, currency, save, closeButton;
  var pickers = [], activePicker = null;
  function t(key) { return root.I18N.t(key); }
  function element(tag, className, text) {
    var node = doc.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }
  function styles() {
    if (doc.getElementById('sf-locale-styles')) return;
    var node = element('style'); node.id = 'sf-locale-styles';
    node.textContent = [
      '.sf-locale-wrap{display:inline-flex;flex-shrink:0}',
      '.sf-locale-toggle{width:40px;height:40px;padding:0;border:1px solid #c7dfce;border-radius:11px;background:#f4f8f5;color:#193923;display:flex;align-items:center;justify-content:center;cursor:pointer}',
      '.sf-locale-toggle svg{width:21px;height:21px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}',
      '.sf-locale-panel{position:fixed;z-index:300;box-sizing:border-box;width:300px;max-width:calc(100vw - 24px);max-height:calc(100dvh - 24px);overflow-y:auto;padding:16px;background:white;color:#193923;border:1px solid #d7e2da;border-radius:14px;box-shadow:0 10px 35px #04361b26;font:13px/1.5 "Segoe UI",Tahoma,Arial,sans-serif;text-align:start}',
      '.sf-locale-panel[hidden]{display:none!important}',
      '.sf-locale-heading{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:8px}',
      '.sf-locale-heading h2{font-size:15px;margin:0;color:#193923}',
      '.sf-locale-close{width:28px;height:28px;flex-shrink:0;display:grid;place-items:center;padding:0;border:0;border-radius:50%;background:#f3f6f4;color:#193923;cursor:pointer;font:22px/1 Arial}',
      '.sf-locale-description{margin:0 0 12px;color:#596d60}',
      '.sf-locale-panel label{display:block;font-size:13px;font-weight:600;margin:10px 0 5px}',
      '.sf-locale-choice{box-sizing:border-box;width:100%;min-height:38px;display:flex;align-items:center;justify-content:space-between;gap:12px;border:1px solid #bdd0c2;border-radius:8px;background:white;color:#193923;padding:7px 10px;font:inherit;text-align:start;cursor:pointer}',
      '.sf-locale-choice svg{width:16px;height:16px;flex-shrink:0;fill:none;stroke:#63766a;stroke-width:2}',
      '.sf-locale-choice[aria-expanded="true"]{border-color:#386c48;box-shadow:0 0 0 1px #386c48}',
      '.sf-locale-options{position:fixed;z-index:310;box-sizing:border-box;overflow-y:auto;overscroll-behavior:contain;scrollbar-gutter:stable;background:white;color:#193923;border:1px solid #d7e2da;border-radius:8px;box-shadow:0 8px 22px #04361b26;padding:4px;font:13px/1.5 "Segoe UI",Tahoma,Arial,sans-serif;text-align:start}',
      '.sf-locale-options[hidden]{display:none!important}',
      '.sf-locale-option{padding:8px 10px;border-radius:4px;cursor:pointer;overflow-wrap:anywhere}',
      '.sf-locale-option:hover,.sf-locale-option[data-active="true"]{background:#edf5ef}',
      '.sf-locale-option[aria-selected="true"]{font-weight:700;color:#17663d}',
      '.sf-locale-note{margin:10px 0;color:#596d60;font-size:12px}',
      '.sf-locale-save{width:100%;min-height:38px;border:0;border-radius:20px;background:#386c48;color:#fff;font:700 14px "Segoe UI",Tahoma,Arial,sans-serif;cursor:pointer;padding:8px 16px}',
      '.sf-locale-save:hover{background:#285237}',
      '.sf-locale-panel :focus-visible,.sf-locale-toggle:focus-visible{outline:3px solid #c9a227;outline-offset:3px}'
    ].join('');
    doc.head.appendChild(node);
  }
  function closePicker() {
    if (!activePicker) return;
    activePicker.list.hidden = true;
    activePicker.control.setAttribute('aria-expanded', 'false');
    activePicker.control.removeAttribute('aria-activedescendant');
    activePicker = null;
  }
  function positionPicker() {
    if (!activePicker) return;
    var rect = activePicker.control.getBoundingClientRect();
    var available = root.innerHeight - rect.bottom - 18;
    // توفير مساحة أسفل الخانة إذا كانت الشاشة قصيرة، دون قلب اتجاه القائمة.
    if (available < 144) {
      var panelTop = parseFloat(panel.style.top) || 12;
      var shift = Math.min(Math.max(0, panelTop - 12), 144 - available);
      panel.style.top = (panelTop - shift) + 'px';
      rect = activePicker.control.getBoundingClientRect();
    }
    var width = Math.min(rect.width, root.innerWidth - 24);
    activePicker.list.style.width = width + 'px';
    activePicker.list.style.left = Math.max(12, Math.min(rect.left, root.innerWidth - width - 12)) + 'px';
    activePicker.list.style.top = (rect.bottom + 6) + 'px';
    activePicker.list.style.maxHeight = Math.max(0, Math.min(280, root.innerHeight - rect.bottom - 18)) + 'px';
  }
  function makePicker(id, label, entries) {
    var control = element('button', 'sf-locale-choice'); control.id = id; control.type = 'button';
    control.setAttribute('role', 'combobox'); control.setAttribute('aria-haspopup', 'listbox');
    control.setAttribute('aria-expanded', 'false'); control.setAttribute('aria-controls', id + '-options');
    control.setAttribute('aria-labelledby', label.id + ' ' + id + '-value');
    var valueText = element('span'); valueText.id = id + '-value'; control.appendChild(valueText);
    var arrow = element('span'); arrow.setAttribute('aria-hidden', 'true');
    arrow.innerHTML = '<svg viewBox="0 0 20 20"><path d="m5 7 5 5 5-5"/></svg>'; control.appendChild(arrow);
    var list = element('div', 'sf-locale-options'); list.id = id + '-options'; list.hidden = true;
    list.setAttribute('role', 'listbox'); list.setAttribute('aria-labelledby', label.id);
    var picker = { control: control, list: list, active: 0 };
    function sync() {
      var selected = entries.findIndex(function (entry) { return entry.value === control.value; });
      valueText.textContent = selected >= 0 ? entries[selected].label : '';
      picker.active = Math.max(0, selected);
      Array.from(list.children).forEach(function (option, index) {
        option.setAttribute('aria-selected', String(index === selected));
        option.setAttribute('data-active', String(index === picker.active));
      });
    }
    function highlight(index) {
      picker.active = Math.max(0, Math.min(index, entries.length - 1));
      Array.from(list.children).forEach(function (option, i) { option.setAttribute('data-active', String(i === picker.active)); });
      var option = list.children[picker.active]; control.setAttribute('aria-activedescendant', option.id);
      if (option.offsetTop < list.scrollTop) list.scrollTop = option.offsetTop;
      else if (option.offsetTop + option.offsetHeight > list.scrollTop + list.clientHeight) list.scrollTop = option.offsetTop + option.offsetHeight - list.clientHeight;
    }
    function expand() {
      closePicker(); sync(); activePicker = picker;
      list.hidden = false; control.setAttribute('aria-expanded', 'true'); positionPicker(); highlight(picker.active);
    }
    function choose(index) { control.value = entries[index].value; sync(); closePicker(); control.focus(); }
    entries.forEach(function (entry, index) {
      var option = element('div', 'sf-locale-option', entry.label); option.id = id + '-option-' + index;
      option.setAttribute('role', 'option'); option.setAttribute('aria-selected', 'false');
      option.addEventListener('pointerdown', function (event) { event.preventDefault(); });
      option.addEventListener('click', function () { choose(index); }); list.appendChild(option);
    });
    control.addEventListener('click', function () { if (activePicker === picker) closePicker(); else expand(); });
    control.addEventListener('keydown', function (event) {
      if (event.key === 'Tab') { closePicker(); return; }
      if (event.key === 'Escape' && activePicker === picker) { event.preventDefault(); event.stopPropagation(); closePicker(); return; }
      if (!['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', ' '].includes(event.key)) return;
      event.preventDefault();
      if (activePicker !== picker) { expand(); if (event.key === 'End') highlight(entries.length - 1); else if (event.key === 'Home') highlight(0); return; }
      if (event.key === 'Enter' || event.key === ' ') choose(picker.active);
      else highlight(event.key === 'Home' ? 0 : event.key === 'End' ? entries.length - 1 : picker.active + (event.key === 'ArrowDown' ? 1 : -1));
    });
    picker.sync = sync; pickers.push(picker); doc.body.appendChild(list);
    return control;
  }
  function position() {
    if (!panel || panel.hidden) return;
    var rect = button.getBoundingClientRect();
    var width = Math.min(300, root.innerWidth - 24);
    var left = doc.documentElement.dir === 'rtl' ? rect.right - width : rect.left;
    panel.style.left = Math.max(12, Math.min(left, root.innerWidth - width - 12)) + 'px';
    var height = panel.offsetHeight;
    var top = rect.bottom + 10;
    if (top + height > root.innerHeight - 12) top = rect.top - height - 10;
    panel.style.top = Math.max(12, Math.min(top, root.innerHeight - height - 12)) + 'px';
    positionPicker();
  }
  function close(restoreFocus) {
    if (!panel) return;
    closePicker();
    panel.hidden = true; button.setAttribute('aria-expanded', 'false');
    if (restoreFocus) button.focus();
  }
  function open() {
    if (!mount()) return;
    language.value = root.I18N.getLang();
    if (!LANGUAGES.some(function (entry) { return entry[2] === language.value; })) language.value = 'ar';
    currency.value = root.SFCurrency.getCode();
    pickers.forEach(function (picker) { picker.sync(); });
    panel.hidden = false; button.setAttribute('aria-expanded', 'true');
    position(); language.focus();
  }
  function apply(event) {
    event.preventDefault();
    var lang = language.value, code = currency.value;
    if (!LANGUAGES.some(function (entry) { return entry[2] === lang; }) || !root.SFCurrency.list().some(function (entry) { return entry.code === code; })) return;
    var changed = lang !== root.I18N.getLang() || code !== root.SFCurrency.getCode();
    if (!changed) { close(true); return; }
    root.SFCurrency.setCode(code);
    root.I18N.setLang(lang);
    close(false);
    root.location.reload();
  }
  function mount() {
    if (button) return true;
    var actions = doc.getElementById('dt-actions');
    if (!actions || !root.I18N || !root.SFCurrency) return false;
    if (doc.getElementById('sf-locale-btn')) return false;
    styles();
    var wrap = element('div', 'sf-locale-wrap');
    button = element('button', 'sf-cur-btn sf-locale-toggle'); button.id = 'sf-locale-btn'; button.type = 'button';
    button.setAttribute('aria-label', t('locale_preferences_title'));
    button.title = t('locale_preferences_title');
    button.setAttribute('aria-haspopup', 'dialog'); button.setAttribute('aria-controls', 'sf-locale-panel'); button.setAttribute('aria-expanded', 'false');
    button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 6.5c4 2 10 2 14 0M5 17.5c4-2 10-2 14 0"/></svg>';
    button.addEventListener('click', function () { if (panel.hidden) open(); else close(true); });
    wrap.appendChild(button);
    var cart = actions.querySelector('a[href="web-cart.html"]');
    if (cart && cart.parentNode === actions) actions.insertBefore(wrap, cart.nextSibling);
    else actions.appendChild(wrap);
    panel = element('form', 'sf-locale-panel'); panel.id = 'sf-locale-panel'; panel.hidden = true;
    panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-labelledby', 'sf-locale-title');
    var heading = element('div', 'sf-locale-heading');
    var title = element('h2', '', t('locale_preferences_title')); title.id = 'sf-locale-title'; heading.appendChild(title);
    closeButton = element('button', 'sf-locale-close', '×'); closeButton.type = 'button'; closeButton.setAttribute('aria-label', t('home_panel_close'));
    closeButton.addEventListener('click', function () { close(true); }); heading.appendChild(closeButton); panel.appendChild(heading);
    var description = element('p', 'sf-locale-description', t('locale_preferences_description')); panel.appendChild(description);
    var langLabel = element('label', '', t('row_language')); langLabel.id = 'sf-locale-language-label'; langLabel.htmlFor = 'sf-locale-language'; panel.appendChild(langLabel);
    var isArabic = root.I18N.getLang() === 'ar';
    language = makePicker('sf-locale-language', langLabel, LANGUAGES.map(function (entry) { return { value: entry[2], label: isArabic ? entry[0] : entry[1] }; }));
    panel.appendChild(language);
    var curLabel = element('label', '', t('currency_pick')); curLabel.id = 'sf-locale-currency-label'; curLabel.htmlFor = 'sf-locale-currency'; panel.appendChild(curLabel);
    currency = makePicker('sf-locale-currency', curLabel, root.SFCurrency.list().map(function (entry) { return { value: entry.code, label: entry.code + ' — ' + (isArabic ? entry.ar : entry.en) }; }));
    panel.appendChild(currency);
    panel.appendChild(element('p', 'sf-locale-note', t('currency_note')));
    save = element('button', 'sf-locale-save', t('locale_preferences_save')); save.type = 'submit'; panel.appendChild(save);
    panel.addEventListener('submit', apply);
    doc.body.appendChild(panel);
    return true;
  }
  doc.addEventListener('pointerdown', function (event) {
    if (activePicker) {
      if (activePicker.list.contains(event.target) || activePicker.control.contains(event.target)) return;
      closePicker();
    }
    if (panel && !panel.hidden && !panel.contains(event.target) && !button.contains(event.target)) close(false);
  });
  doc.addEventListener('focusin', function (event) {
    if (activePicker && (activePicker.list.contains(event.target) || activePicker.control.contains(event.target))) return;
    closePicker();
    if (panel && !panel.hidden && !panel.contains(event.target) && !button.contains(event.target)) close(false);
  });
  doc.addEventListener('keydown', function (event) {
    if (activePicker && event.key === 'Escape') { event.preventDefault(); closePicker(); return; }
    if (panel && !panel.hidden && event.key === 'Escape') { event.preventDefault(); close(true); }
  });
  root.addEventListener('resize', position);
  root.addEventListener('scroll', function (event) {
    if (!activePicker || event.target !== activePicker.list) position();
  }, true);
  if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', mount);
  else mount();
  root.SFCurrencyUI = { open: open, close: close, mount: mount };
  root.SFLang = { open: open, close: close };
})(window);
