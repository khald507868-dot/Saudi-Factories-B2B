/* Negotiated, conversation-scoped offers. Server RPCs own all prices and orders. */
(function (root) {
  'use strict';
  var context, dialog, button, offers = {}, requestKey, busy = false, draftThread = null;
  var t = function (key) { return root.I18N.t('offer_' + key); };
  function esc(value) { return String(value == null ? '' : value).replace(/[&<>"']/g, function (c) {
    return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
  }); }
  function money(value) { return root.I18N.money(Number(value).toFixed(2)); }
  function rpc(name, args) {
    return root.sb.rpc(name, args).then(function (r) {
      if (r.error) throw r.error;
      var data = Array.isArray(r.data) ? r.data[0] : r.data;
      if (!data) throw new Error('offer_unavailable');
      return data;
    });
  }
  function status(q) { return q.status === 'pending' && new Date(q.expires_at).getTime() <= Date.now() ? 'expired' : q.status; }
  function totals(price, quantity) {
    var subtotal = Math.round(Number(price) * 100) * Number(quantity);
    var fee = Math.round(subtotal / 100);
    var vat = Math.round((subtotal + fee) * 15 / 100);
    return { subtotal: subtotal / 100, shipping: 0, shipping_pricing: 'quote', payment_fee: fee / 100,
      vat_amount: vat / 100, total: (subtotal + fee + vat) / 100 };
  }
  function costsHTML(q) {
    return '<dl class="offer-costs">' + ['subtotal','shipping','payment_fee','vat_amount','total'].map(function (key) {
      return '<div><dt>' + esc(key === 'total' && q.shipping_pricing === 'quote' ? root.I18N.t('shipping_before_total') : t(key)) + '</dt><dd>' + (key === 'shipping' && q.shipping_pricing === 'quote' ? esc(root.I18N.t('shipping_pending')) : money(q[key])) + '</dd></div>';
    }).join('') + '</dl>';
  }
  function cardHTML(q, readonly) {
    offers[q.id] = q;
    var state = status(q), uid = root.SF_USER && root.SF_USER.id;
    var image = root.sfSafeHttpUrl ? root.sfSafeHttpUrl(q.product_image) : '';
    var actions = '';
    if (!readonly && state === 'pending') {
      if (uid === q.buyer_id) actions = '<button type="button" data-offer-action="accept" data-offer-id="'+esc(q.id)+'">'+esc(t('accept'))+'</button>' +
        '<button type="button" class="offer-secondary" data-offer-action="declined" data-offer-id="'+esc(q.id)+'">'+esc(t('decline'))+'</button>';
      if (uid === q.seller_id) actions = '<button type="button" class="offer-secondary" data-offer-action="withdrawn" data-offer-id="'+esc(q.id)+'">'+esc(t('withdraw'))+'</button>';
    }
    if (!readonly && state === 'accepted') actions = '<a class="offer-order-link" href="'+(q.shipping_pricing === 'quote' ? 'web-shipping.html?order='+encodeURIComponent(q.order_id) : 'web-orders.html')+'">'+esc(t('view_order'))+'</a>';
    return '<article class="private-offer-card"><header><strong>'+esc(t('title'))+'</strong><span>'+esc(t(state))+'</span></header>' +
      '<div class="offer-product">'+(image?'<img alt="" src="'+esc(image)+'">':'')+'<strong>'+esc(q.product_name)+'</strong></div>'+
      '<p>'+esc(t('quantity'))+': <b dir="ltr">'+esc(q.quantity)+'</b></p><p>'+esc(t('unit_price'))+': '+money(q.unit_price)+'</p>'+
      costsHTML(q)+(q.notes?'<p class="offer-notes">'+esc(q.notes)+'</p>':'')+
      '<p class="offer-expiry">'+esc(t('expires'))+': '+esc(new Date(q.expires_at).toLocaleString(root.I18N.getLang() === 'ar' ? 'ar-SA' : 'en-GB'))+'</p>'+
      '<div class="offer-actions">'+actions+'</div></article>';
  }
  function close() { if (!busy && dialog.open) { dialog.close(); draftThread = null; } }
  function setBusy(value) {
    busy = value;
    dialog.querySelectorAll('input,select,textarea,button').forEach(function (el) { el.disabled = value; });
  }
  function error(err) {
    var code = err && err.message || '';
    dialog.querySelector('[role="status"]').textContent = /offer_shipping_reissue_required/.test(code) ? root.I18N.t('shipping_reissue') : /offer_unavailable/.test(code) ? t('unavailable') : /offer_access_denied/.test(code) ? t('access_denied') : t('failed');
  }
  function shell(title, content) {
    dialog.innerHTML = '<div class="offer-dialog-head"><h2 id="private-offer-title">'+esc(title)+'</h2><button type="button" data-offer-close aria-label="'+esc(t('cancel'))+'">×</button></div>'+content+
      '<p class="offer-error" role="status"></p>';
    if (!dialog.open) dialog.showModal();
  }
  function loadProducts(thread) {
    var rows = [];
    function page(offset) {
      return root.sb.from('products').select('id,name,price,tiers,moq').eq('factory_id', thread.factory_id)
        .order('id').range(offset, offset + 99).then(function (r) {
          if (r.error) throw r.error;
          rows = rows.concat(r.data || []);
          return (r.data || []).length === 100 ? page(offset + 100) : rows;
        });
    }
    return page(0);
  }
  function openDraft() {
    var thread = context.getThread();
    if (!thread || thread.role !== 'individual' || !root.SF_PROFILE || root.SF_PROFILE.account_type !== 'factory') return;
    draftThread = thread;
    requestKey = root.crypto.randomUUID();
    shell(t('title'), '<p>'+esc(t('loading'))+'</p>');
    loadProducts(thread).then(function (products) {
      if (!dialog.open || draftThread !== thread) return;
      if (!products.length) { shell(t('title'), '<p>'+esc(t('no_products'))+'</p>'); return; }
      shell(t('title'), '<p class="offer-recipient">'+esc(t('recipient'))+': <strong>'+esc(thread.name)+'</strong></p>'+
        '<form id="private-offer-form"><label>'+esc(t('product'))+'<select name="product" required><option value="">'+esc(t('choose_product'))+'</option>'+
        products.map(function (p) { return '<option value="'+esc(p.id)+'">'+esc(p.name)+'</option>'; }).join('')+'</select></label><p id="offer-public-price"></p>'+
        '<div class="offer-fields"><label>'+esc(t('quantity'))+'<input name="quantity" type="number" min="1" max="100000" step="1" value="1" required></label>'+
        '<label>'+esc(t('special_price'))+' (SAR)<input name="price" type="number" min="0.01" max="1000000" step="0.01" required></label></div>'+
        '<label>'+esc(t('valid_days'))+'<input name="days" type="number" min="1" max="30" step="1" value="7" required></label>'+
        '<label>'+esc(t('notes'))+'<textarea name="notes" maxlength="1000" rows="2"></textarea></label>'+
        '<p class="offer-hint">'+esc(t('charges_hint'))+'</p><div id="offer-preview"></div><div class="offer-actions">'+
        '<button type="submit">'+esc(t('send'))+'</button><button type="button" class="offer-secondary" data-offer-close>'+esc(t('cancel'))+'</button></div></form>');
      var form = dialog.querySelector('form');
      form.addEventListener('input', function () {
        requestKey = root.crypto.randomUUID();
        var product = products.find(function (p) { return String(p.id) === form.elements.product.value; });
        dialog.querySelector('#offer-public-price').innerHTML = product ? esc(t('public_price'))+': '+root.SFProductCard.priceHTML(product) : '';
        var price = Number(form.elements.price.value), qty = Number(form.elements.quantity.value);
        dialog.querySelector('#offer-preview').innerHTML = price > 0 && price <= 1000000 && Number.isInteger(qty) && qty > 0 && qty <= 100000 ? costsHTML(totals(price,qty)) : '';
      });
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        if (busy || !form.reportValidity()) return;
        var args = { p_conversation_id: Number(thread.conversation_id), p_product_id: Number(form.elements.product.value),
          p_quantity: Number(form.elements.quantity.value), p_unit_price: Number(form.elements.price.value),
          p_valid_days: Number(form.elements.days.value), p_notes: form.elements.notes.value.trim(), p_request_key: requestKey };
        setBusy(true);
        rpc('create_private_chat_offer', args).then(function () {
          setBusy(false); close(); context.refresh();
        }).catch(function (err) { setBusy(false); error(err); });
      });
      form.elements.product.focus();
    }).catch(function (err) { if (dialog.open && draftThread === thread) error(err); });
  }
  function openAction(q, action) {
    shell(action === 'accept' ? t('accept') : t(action === 'declined' ? 'decline' : 'withdraw'),
      cardHTML(q,true)+'<p class="offer-hint">'+esc(action === 'accept' ? t('confirm_hint') : t('close_hint'))+'</p>'+
      '<div class="offer-actions"><button type="button" id="offer-confirm">'+esc(action === 'accept' ? t('confirm_order') : t('confirm'))+'</button>'+
      '<button type="button" class="offer-secondary" data-offer-close>'+esc(t('cancel'))+'</button></div>');
    dialog.querySelector('#offer-confirm').addEventListener('click', function () {
      if (busy) return;
      setBusy(true);
      var job = action === 'accept' ? rpc('accept_private_chat_offer',{p_offer_id:q.id}) : rpc('close_private_chat_offer',{p_offer_id:q.id,p_action:action});
      job.then(function (updated) {
        offers[q.id] = updated; setBusy(false); close(); context.refresh();
      }).catch(function (err) { setBusy(false); error(err); context.refresh(); });
    });
  }
  root.SFPrivateOffers = {
    totals: totals, cardHTML: cardHTML,
    load: function (conversationId) {
      return root.sb.from('private_chat_offers').select('*').eq('conversation_id', Number(conversationId))
        .then(function (r) {
          if (r.error) throw r.error;
          var byMessage = {}; (r.data || []).forEach(function (q) { byMessage[String(q.message_id)] = q; offers[q.id] = q; });
          return byMessage;
        });
    },
    updateThread: function (thread) {
      if (button) button.hidden = !(thread && thread.role === 'individual' && root.SF_PROFILE && root.SF_PROFILE.account_type === 'factory');
      if (dialog && dialog.open && !busy) close();
    },
    init: function (options) {
      context = options; button = document.getElementById('private-offer-btn');
      button.title = t('title'); button.setAttribute('aria-label',t('title'));
      dialog = document.createElement('dialog'); dialog.id = 'private-offer-dialog';
      dialog.className = 'private-offer-dialog'; dialog.setAttribute('aria-labelledby','private-offer-title');
      document.body.appendChild(dialog);
      button.addEventListener('click', openDraft);
      dialog.addEventListener('cancel', function (event) { event.preventDefault(); close(); });
      dialog.addEventListener('click', function (event) { if (event.target.closest('[data-offer-close]')) close(); });
      document.getElementById('messages-area').addEventListener('click', function (event) {
        var target = event.target.closest('[data-offer-action]');
        if (!target) return;
        var q = offers[target.getAttribute('data-offer-id')];
        if (q) openAction(q,target.getAttribute('data-offer-action'));
      });
    }
  };
})(window);
