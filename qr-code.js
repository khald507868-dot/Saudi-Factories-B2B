/* ============================================================
   مولّد رمز الاستجابة السريعة — SFQR
   ------------------------------------------------------------
   مكتوب في الكود لا مكتبة خارجية، على قاعدة المشروع: لا ملفّ
   صورة واحد، وكل رسم يُبنى بالكود.

   يكفي هنا نسخة مختصرة: النسخة 5 (37×37 وحدة) بمستوى تصحيح
   منخفض، وهي تتّسع لنحو 106 بايت — أكثر ممّا يحتاجه رمز فاتورة
   هيئة الزكاة والضريبة والجمارك في هذا المشروع.

   الترميز بايتيّ (byte mode) لأنّ محتوى الرمز TLV بترميز
   base64، وفيه محارف لا يقبلها الوضع الأبجدي الرقمي.
   ============================================================ */
(function (global) {
  "use strict";

  /* ---------- حساب في حقل غالوا GF(256) ---------- */
  var EXP = new Array(512);
  var LOG = new Array(256);
  (function initTables() {
    var x = 1;
    for (var i = 0; i < 255; i++) {
      EXP[i] = x;
      LOG[x] = i;
      x <<= 1;
      /* 0x11d هو كثير الحدود المولّد المعتمد في مواصفة QR */
      if (x & 0x100) x ^= 0x11d;
    }
    for (var j = 255; j < 512; j++) EXP[j] = EXP[j - 255];
  })();

  function gfMul(a, b) {
    if (a === 0 || b === 0) return 0;
    return EXP[LOG[a] + LOG[b]];
  }

  /* كثير حدود المولّد لعدد معيّن من بايتات التصحيح */
  function rsGenerator(n) {
    var poly = [1];
    for (var i = 0; i < n; i++) {
      var next = new Array(poly.length + 1).fill(0);
      for (var j = 0; j < poly.length; j++) {
        next[j] ^= poly[j];
        next[j + 1] ^= gfMul(poly[j], EXP[i]);
      }
      poly = next;
    }
    return poly;
  }

  function rsEncode(data, ecLen) {
    var gen = rsGenerator(ecLen);
    var res = new Array(ecLen).fill(0);
    for (var i = 0; i < data.length; i++) {
      var factor = data[i] ^ res[0];
      res.shift();
      res.push(0);
      if (factor !== 0) {
        for (var j = 0; j < gen.length - 1; j++) {
          res[j] ^= gfMul(gen[j + 1], factor);
        }
      }
    }
    return res;
  }

  /* ---------- معطيات النسخة 5 بمستوى L ----------
     37×37 وحدة، كتلة واحدة: 108 بايت بيانات + 26 تصحيح. */
  var SIZE = 37;
  var DATA_BYTES = 108;
  var EC_BYTES = 26;
  var ALIGN = [6, 30];   /* مراكز أنماط المحاذاة */

  function makeMatrix() {
    var m = [];
    for (var i = 0; i < SIZE; i++) m.push(new Array(SIZE).fill(null));
    return m;
  }

  function placeFinder(m, r, c) {
    for (var dr = -1; dr <= 7; dr++) {
      for (var dc = -1; dc <= 7; dc++) {
        var rr = r + dr, cc = c + dc;
        if (rr < 0 || rr >= SIZE || cc < 0 || cc >= SIZE) continue;
        var inner = dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4;
        var ring = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6 &&
                   (dr === 0 || dr === 6 || dc === 0 || dc === 6);
        m[rr][cc] = (inner || ring) ? 1 : 0;
      }
    }
  }

  function placeFunctionPatterns(m) {
    placeFinder(m, 0, 0);
    placeFinder(m, 0, SIZE - 7);
    placeFinder(m, SIZE - 7, 0);

    /* أنماط التوقيت */
    for (var i = 8; i < SIZE - 8; i++) {
      var v = (i % 2 === 0) ? 1 : 0;
      if (m[6][i] === null) m[6][i] = v;
      if (m[i][6] === null) m[i][6] = v;
    }

    /* أنماط المحاذاة — تُتخطّى حيث تصطدم بأنماط البحث */
    ALIGN.forEach(function (r) {
      ALIGN.forEach(function (c) {
        if ((r === 6 && c === 6) || (r === 6 && c === 30) ||
            (r === 30 && c === 6)) return;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            var on = Math.max(Math.abs(dr), Math.abs(dc)) !== 1;
            m[r + dr][c + dc] = on ? 1 : 0;
          }
        }
      });
    });

    /* الوحدة الداكنة الثابتة */
    m[SIZE - 8][8] = 1;
  }

  /* مواضع معلومات الصيغة، تُحجز قبل رصّ البيانات */
  function reserveFormat(m) {
    for (var i = 0; i <= 8; i++) {
      if (m[8][i] === null) m[8][i] = 0;
      if (m[i][8] === null) m[i][8] = 0;
    }
    for (var j = 0; j < 8; j++) {
      if (m[8][SIZE - 1 - j] === null) m[8][SIZE - 1 - j] = 0;
      if (m[SIZE - 1 - j][8] === null) m[SIZE - 1 - j][8] = 0;
    }
  }

  /* قناع رقم 0: (row + col) % 2 === 0 */
  function maskBit(r, c) { return (r + c) % 2 === 0; }

  function placeData(m, bits) {
    var idx = 0;
    var up = true;
    for (var right = SIZE - 1; right > 0; right -= 2) {
      if (right === 6) right--;   /* عمود التوقيت يُتخطّى */
      for (var v = 0; v < SIZE; v++) {
        var row = up ? SIZE - 1 - v : v;
        for (var k = 0; k < 2; k++) {
          var col = right - k;
          if (m[row][col] !== null) continue;
          var bit = idx < bits.length ? bits[idx] : 0;
          idx++;
          if (maskBit(row, col)) bit ^= 1;
          m[row][col] = bit;
        }
      }
      up = !up;
    }
  }

  /* معلومات الصيغة للمستوى L مع القناع 0 — قيمة ثابتة من
     المواصفة، فلا حاجة لإعادة حساب BCH في كل استدعاء. */
  var FORMAT_BITS = 0x77C4;

  function placeFormat(m) {
    var bits = [];
    for (var i = 14; i >= 0; i--) bits.push((FORMAT_BITS >> i) & 1);

    /* النسخة الأولى حول نمط البحث الأعلى الأيسر */
    var coords1 = [[8,0],[8,1],[8,2],[8,3],[8,4],[8,5],[8,7],[8,8],
                   [7,8],[5,8],[4,8],[3,8],[2,8],[1,8],[0,8]];
    coords1.forEach(function (p, i) { m[p[0]][p[1]] = bits[i]; });

    /* النسخة الثانية موزّعة على الحافتين الأخريين */
    for (var j = 0; j < 7; j++) m[SIZE - 1 - j][8] = bits[j];
    for (var k = 0; k < 8; k++) m[8][SIZE - 8 + k] = bits[7 + k];

    m[SIZE - 8][8] = 1;
  }

  /* ---------- البناء ---------- */
  function encode(text) {
    var bytes = [];
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 0x80) bytes.push(c);
      else if (c < 0x800) {
        bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
      } else {
        bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F),
                   0x80 | (c & 0x3F));
      }
    }

    if (bytes.length > DATA_BYTES - 3) return null;   /* لا يتّسع */

    var bits = [];
    function push(value, len) {
      for (var i = len - 1; i >= 0; i--) bits.push((value >> i) & 1);
    }

    push(4, 4);                    /* وضع البايت */
    push(bytes.length, 16);        /* عدّاد الطول للنسخة 5 */
    bytes.forEach(function (b) { push(b, 8); });
    push(0, 4);                    /* منهي، يُقصّ إن تجاوز */

    while (bits.length % 8) bits.push(0);

    var data = [];
    for (var b = 0; b < bits.length; b += 8) {
      var v = 0;
      for (var k = 0; k < 8; k++) v = (v << 1) | bits[b + k];
      data.push(v);
    }

    /* بايتات الحشو المعتمدة في المواصفة */
    var pad = [0xEC, 0x11], pi = 0;
    while (data.length < DATA_BYTES) data.push(pad[pi++ % 2]);

    var ec = rsEncode(data, EC_BYTES);
    var all = data.concat(ec);

    var finalBits = [];
    all.forEach(function (byte) {
      for (var i = 7; i >= 0; i--) finalBits.push((byte >> i) & 1);
    });

    var m = makeMatrix();
    placeFunctionPatterns(m);
    reserveFormat(m);
    placeData(m, finalBits);
    placeFormat(m);
    return m;
  }

  /* يُرجع <svg> جاهزاً للإدراج، أو نصّاً فارغاً عند التعذّر */
  function svg(text, px) {
    var m = encode(String(text || ""));
    if (!m) return "";

    var quiet = 4;                     /* الهامش الصامت الإلزامي */
    var total = SIZE + quiet * 2;
    var out = '<svg viewBox="0 0 ' + total + " " + total + '" ' +
              'width="' + (px || 220) + '" height="' + (px || 220) + '" ' +
              'shape-rendering="crispEdges" role="img">' +
              '<rect width="' + total + '" height="' + total + '" fill="#ffffff"></rect>';

    for (var r = 0; r < SIZE; r++) {
      for (var c = 0; c < SIZE; c++) {
        if (m[r][c]) {
          out += '<rect x="' + (c + quiet) + '" y="' + (r + quiet) +
                 '" width="1" height="1" fill="#000000"></rect>';
        }
      }
    }
    return out + "</svg>";
  }

  /* ---------- محتوى رمز الفاتورة (TLV ثم base64) ----------
     الحقول الخمسة الإلزامية: اسم البائع، رقمه الضريبي، الطابع
     الزمني، الإجمالي شامل الضريبة، مبلغ الضريبة. */
  function tlv(tag, value) {
    var bytes = [];
    for (var i = 0; i < value.length; i++) {
      var c = value.charCodeAt(i);
      if (c < 0x80) bytes.push(c);
      else if (c < 0x800) bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
      else bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F),
                     0x80 | (c & 0x3F));
    }
    return [tag, bytes.length].concat(bytes);
  }

  function invoicePayload(seller, vatNumber, timestamp, total, vat) {
    var bytes = []
      .concat(tlv(1, String(seller)))
      .concat(tlv(2, String(vatNumber)))
      .concat(tlv(3, String(timestamp)))
      .concat(tlv(4, String(total)))
      .concat(tlv(5, String(vat)));

    var bin = "";
    bytes.forEach(function (b) { bin += String.fromCharCode(b); });
    try { return global.btoa(bin); } catch (e) { return ""; }
  }

  global.SFQR = { svg: svg, invoicePayload: invoicePayload };
})(window);
