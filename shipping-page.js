/* نماذج الشحن اليدوي. الخادم يتحقق من الصلاحيات والأسعار وكل انتقال حالة. */
(function (root) {
  'use strict';
  var rows = [], selected, busy = false, offset = 0, generation = 0;
  var $ = function (id) { return document.getElementById(id); };
  var say = function (ar,en) { return root.I18N.getLang() === 'ar' ? ar : en; };
  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
  function text(ar,en) { return esc(say(ar,en)); }
  function date(v) { return v ? new Date(v).toLocaleString(root.I18N.getLang()==='ar'?'ar-SA':'en-GB') : '—'; }
  function money(v) { return Number(v).toFixed(2) + ' SAR'; }
  function localDate(v) { if (!v) return ''; var d = new Date(v); return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16); }
  var states = {
    awaiting_details:['بانتظار الوجهة والتغليف','Awaiting destination and packing'],awaiting_quote:['بانتظار عرض الشحن','Awaiting shipping quote'],
    quoted:['عرض الشحن جاهز','Shipping quote ready'],booking_requested:['بانتظار تأكيد الحجز','Booking requested'],booked:['تم تأكيد الحجز','Booking confirmed'],
    collected:['تم الاستلام من المصنع','Collected from factory'],departed:['غادرت الشحنة','Departed'],arrived:['وصلت الشحنة','Arrived'],delivered:['تم التسليم','Delivered'],cancelled:['ملغي','Cancelled'],
    destination:['أكد المشتري الطلب وعنوان التوصيل','Buyer confirmed the order and delivery address'],packing:['أكد المصنع بيانات الشحنة','Factory confirmed shipment details'],quote:['تم تقديم عرض شركة الشحن','Carrier quote submitted'],
    buyer_details_needed:['بانتظار تأكيد المشتري للطلب والعنوان','Awaiting buyer order and address confirmation'],payment:['تم تأكيد استلام الدفع','Payment receipt confirmed'],
    pickup_ready:['أكد المصنع جاهزية الشحنة للاستلام','Factory confirmed shipment ready for pickup'],pickup_ready_needed:['تم الدفع؛ على المصنع تأكيد جاهزية الشحنة','Paid; factory pickup readiness confirmation needed'],
    production_needed:['تم الدفع؛ بانتظار بدء الإنتاج من المصنع','Paid; awaiting factory production'],production_started:['بدأ المصنع الإنتاج','Factory started production'],production_completed:['أكد المصنع انتهاء الإنتاج','Factory completed production'],
    accept:['وافق المشتري على العرض؛ بانتظار الدفع','Buyer accepted the quote; awaiting payment'],decline:['طُلب عرض بديل','Replacement quote requested'],book:['تأكيد حجز الشركة','Carrier booking confirmed'],cancel:['أُلغي الطلب','Order cancelled'],packing_needed:['طلب جديد يحتاج بيانات التغليف','New order needs packing details']
  };
  function label(key) { var pair=states[key]; return pair?say(pair[0],pair[1]):key; }
  function uploading() { return !!(root.SFShippingImages&&root.SFShippingImages.isBusy()); }
  function photosMarkup(paths,editable) { return '<div class="wide shipping-package-photos" data-shipping-photos data-editable="'+String(editable)+'" data-paths="'+esc(JSON.stringify(Array.isArray(paths)?paths:[]))+'"></div>'; }
  async function query(job) { var r=await job; if(r.error) throw r.error; return r.data; }
  function showError(err) {
    if(err&&['PGRST202','42883'].includes(err.code))err={message:'shipping_domestic_setup_required'};
    var msg=err && err.message || String(err), key=msg.match(/shipping_[a-z_]+/);
    var map={shipping_stale:['تغيّرت بيانات الطلب. حدّث الصفحة وراجع العرض قبل المحاولة.','The request changed. Refresh and review it before retrying.'],
      shipping_quote_expired:['انتهت صلاحية العرض. اطلب عرضاً بديلاً.','This quote expired. Request a replacement.'],
      shipping_access_denied:['لا يملك هذا الحساب صلاحية هذا الإجراء.','This account cannot perform this action.'],
      shipping_locked:['لا يمكن تعديل البيانات في هذه المرحلة.','These details are locked at this stage.'],
      shipping_buyer_confirmation_required:['يلزم تأكيد المشتري للطلب والعنوان أولًا.','The buyer must confirm the order and address first.'],
      shipping_factory_confirmation_required:['يلزم تأكيد المصنع لبيانات الشحنة قبل التسعير.','The factory must confirm shipment details before pricing.'],
      shipping_payment_required:['يلزم تأكيد استلام الدفع قبل حجز الشحنة.','Payment receipt must be confirmed before booking.'],
      shipping_pickup_ready_required:['بانتظار تأكيد المصنع أن الشحنة جاهزة للاستلام.','Awaiting factory confirmation that the shipment is ready for pickup.'],
      shipping_production_start_required:['أكد بدء الإنتاج أولًا.','Confirm production start first.'],
      shipping_production_required:['يلزم تأكيد انتهاء الإنتاج قبل جاهزية الشحنة.','Confirm production completion before pickup readiness.'],
      shipping_invalid_images:['تعذّر حفظ صور التغليف. أعد رفع الصور وتأكد أنها تخص هذه الشحنة.','Unable to save packing images. Upload images belonging to this shipment.'],
      shipping_images_unavailable:['لم يكتمل تحميل خدمة الصور. حدّث الصفحة قبل حفظ بيانات التغليف.','The image service has not loaded. Refresh before saving packing details.'],
      shipping_image_limit:['الحد 5 صور لكل مجموعة تغليف و20 صورة للشحنة.','Limit: 5 images per package group and 20 per shipment.'],
      shipping_saved_address_missing:['لا يوجد عنوان سعودي محفوظ. أضف عنوان توصيل من صفحة «العنوان» في حسابك ثم حدّث هذه الصفحة.','No saved Saudi delivery address. Add an address from the Address page in your account, then refresh this page.'],
      shipping_saved_address_not_domestic:['العنوان الافتراضي خارج السعودية أو يحتاج مراجعة. اختر عنوانًا داخل السعودية من صفحة «العنوان».','Your default address is outside Saudi Arabia or needs review. Select a domestic address from the Address page.'],
      shipping_contact_missing:['أكمل اسمك ورقم هاتفك في ملفك الشخصي لاستخدام العنوان المحفوظ.','Complete your name and phone in your profile to use the saved address.'],
      shipping_domestic_setup_required:['خيار العنوان المحفوظ يحتاج تحديث الشحن الجديد في Supabase.','The saved-address option requires the new shipping update in Supabase.'],
      shipping_invalid_pickup:['موعد الاستلام يجب أن يكون مستقبلياً وبعد جاهزية المصنع.','Pickup must be in the future and after factory readiness.'],
      shipping_invalid_ready_at:['حدد موعد جاهزية مستقبلياً خلال سنة.','Choose a future readiness time within one year.'],
      shipping_invalid_expiry:['حدد صلاحية مستقبلية خلال 90 يوماً.','Quote expiry must be in the future within 90 days.'],
      shipping_invalid_transition:['لا يمكن تسجيل هذه المرحلة بعد. تحقق من الحجز وموعد الاستلام.','This stage is not available yet. Check booking and pickup time.']};
    $('shipping-error').hidden=false; $('shipping-error').textContent=key&&map[key[0]]?say.apply(null,map[key[0]]):say('تعذّر إتمام الإجراء. تحقق من الحقول والاتصال ثم أعد المحاولة.','Unable to complete this action. Check the fields and connection, then retry.');
  }
  function field(name,ar,en,value,type,extra) {
    return '<label>'+text(ar,en)+'<input name="'+name+'" type="'+(type||'text')+'" value="'+esc(value)+'" '+(extra||'required maxlength="150"')+'></label>';
  }
  function area(name,ar,en,value,max) { return '<label class="wide">'+text(ar,en)+'<textarea name="'+name+'" maxlength="'+(max||3000)+'" required>'+esc(value)+'</textarea></label>'; }
  function option(value,ar,en,current) { return '<option value="'+value+'"'+(value===current?' selected':'')+'>'+text(ar,en)+'</option>'; }
  function isSaudiCountry(value) {
    return ['sa','sau','ksa','saudi arabia','kingdom of saudi arabia','السعودية','السعوديه','المملكة العربية السعودية','المملكه العربيه السعوديه'].includes(String(value||'').trim().toLowerCase().replace(/\s+/g,' '));
  }
  function destinationScope(d) {
    if(d.scope==='domestic'||d.scope==='international') return d.scope;
    return d.country ? (isSaudiCountry(d.country)?'domestic':'international') : '';
  }
  function destinationChoice(scope) {
    var pin='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>';
    var globe='<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z"/></svg>';
    return '<fieldset class="shipping-scope wide"><legend>'+text('وجهة التوصيل','Delivery destination')+'</legend><div class="shipping-scope-options">'+
      [['domestic','داخل السعودية','Inside Saudi Arabia',pin],['international','خارج السعودية','Outside Saudi Arabia',globe]].map(function(item){
        return '<label class="shipping-scope-option"><input type="radio" name="destination_scope" value="'+item[0]+'" required'+(scope===item[0]?' checked':'')+'><span>'+item[3]+'<strong>'+text(item[1],item[2])+'</strong></span></label>';
      }).join('')+'</div></fieldset>';
  }
  function syncDestinationScope(el) {
    var scope=el.elements.destination_scope.value;
    var details=el.querySelector('[data-destination-fields]');
    details.hidden=scope!=='international'; details.disabled=scope!=='international';
    el.querySelector('[data-domestic-note]').hidden=scope!=='domestic';
    var savedButton=el.querySelector('[data-use-saved-address]');
    savedButton.hidden=scope!=='domestic'; savedButton.disabled=busy||!!el._domesticLoading;
    var submit=el.querySelector('button[type="submit"]');
    submit.disabled=busy||!scope||(scope==='domestic'&&(!el._domesticDestination||el._domesticLoading));
    submit.textContent=say('تأكيد الطلب والعنوان وإرساله للمصنع','Confirm order and address; send to factory');
    el.elements.country.setCustomValidity(scope==='international'&&isSaudiCountry(el.elements.country.value)?say('للشحن إلى السعودية اختر «داخل السعودية».','For Saudi delivery, select Inside Saudi Arabia.'):'');
    el.elements.port.required=scope==='international'&&el.elements.delivery_type.value==='port';
  }
  async function loadDomesticDestination(el,s,useSaved) {
    if((useSaved&&busy)||el._domesticLoading||(!useSaved&&el._domesticDestination))return;
    el._domesticLoading=true;
    if(useSaved) { el._domesticDestination=null; el._useSavedAddress=true; }
    var note=el.querySelector('[data-domestic-note]');
    note.textContent=say('جارٍ تحميل عنوانك المحفوظ…','Loading your saved address…');
    syncDestinationScope(el);
    try {
      var dest=await query(root.sb.rpc(el._useSavedAddress?'get_saved_shipping_destination':'get_domestic_shipping_destination',{p_order_id:s.order_id}));
      if(el.isConnected===false)return;
      el._domesticDestination=dest;
      var prefix=el._useSavedAddress?say('عنوان حسابك الافتراضي — راجعه ثم أكد الربط: ','Your default account address — review, then confirm linking: '):
        (s.destination&&isSaudiCountry(s.destination.country)?say('الوجهة الحالية للشحنة: ','Current shipment destination: '):say('سيُستخدم عنوانك المحفوظ: ','Your saved address will be used: '));
      note.textContent=dest?prefix+[dest.address,dest.city].filter(Boolean).join(' · '):
        say('لا يوجد عنوان سعودي محفوظ. أضف عنوان توصيل من صفحة «العنوان» في حسابك، ثم اضغط «تحديث».','No saved Saudi address. Add an address from the Address page in your account, then select Refresh.');
    } catch(err) {
      if(el.isConnected===false)return;
      note.textContent=say('تعذّر تحميل العنوان المحفوظ.','Unable to load the saved address.');
      if(err&&['PGRST202','42883'].includes(err.code))err={message:'shipping_domestic_setup_required'};
      showError(err);
    } finally {
      el._domesticLoading=false;
      if(el.isConnected!==false)syncDestinationScope(el);
    }
  }
  function form(action,title,fields,button) { return '<form data-action="'+action+'"><h3>'+title+'</h3><div class="shipping-fields">'+fields+'</div><button type="submit">'+button+'</button></form>'; }
  function line(ar,en,value,isTotal) { return '<div'+(isTotal?' class="total"':'')+'><dt>'+text(ar,en)+'</dt><dd>'+esc(value)+'</dd></div>'; }
  function approvals(s) {
    return {buyer:s.buyer_confirmed_at===undefined?!!s.destination:!!s.buyer_confirmed_at,
      factory:s.factory_confirmed_at===undefined?!!s.packing:!!s.factory_confirmed_at};
  }
  function isPaid(o) { return ['paid','processing','shipped','completed'].includes(o.status); }
  function pickupReady(s) { return !!s.pickup_ready_at||['booked','collected','departed','arrived','delivered'].includes(s.status); }
  function productionComplete(s) { return !!s.production_completed_at||pickupReady(s); }
  function shipmentLabel(s) {
    if(s.orders&&s.orders.status==='awaiting_payment')return say('بانتظار الدفع','Awaiting payment');
    if(s.status==='booking_requested'&&s.orders&&isPaid(s.orders))return pickupReady(s)?say('جاهزة لاستلام شركة الشحن','Ready for carrier pickup'):productionComplete(s)?say('بانتظار جاهزية الشحنة من المصنع','Awaiting factory pickup readiness'):s.production_started_at?say('تحت الإنتاج','In production'):say('بانتظار بدء الإنتاج','Awaiting production start');
    if(s.status==='awaiting_details')return approvals(s).buyer?say('بانتظار تأكيد المصنع','Awaiting factory confirmation'):say('بانتظار تأكيد المشتري','Awaiting buyer confirmation');
    return label(s.status);
  }
  /* Decorative stage illustrations; shipment status is conveyed by the text. */
  function stageArt(index) {
    var parcel='<path class="shipping-art-fill" d="m73 28 16-8 16 8v20l-16 8-16-8Z"/><path d="m73 28 16 8 16-8M89 36v20M81 24l16 8v7"/>';
    var truck='<path class="shipping-art-fill" d="M20 23h49v26H20Z"/><path d="M69 32h16l12 12v5H69M77 32v11h18"/><circle class="shipping-art-wheel" cx="34" cy="50" r="6"/><circle class="shipping-art-wheel" cx="82" cy="50" r="6"/>';
    var scenes=[
      '<circle cx="39" cy="20" r="9"/><path class="shipping-art-fill" d="M21 51V43c0-10 8-15 18-15s18 5 18 15v8Z"/><g class="shipping-art-float"><path class="shipping-art-fill" d="M77 14h23v35H77Z"/><path d="M83 24h11M83 31h11M83 38h6"/><path class="shipping-art-accent" d="m68 43 5 5 9-10"/></g>',
      '<path class="shipping-art-fill" d="M18 51V29l17-9v12l17-10v11h18v18ZM55 32V14h9l3 18"/><path d="M27 39h7v7h-7ZM43 39h7v7h-7Z"/><g class="shipping-art-float">'+parcel+'</g>',
      '<g class="shipping-art-drive">'+truck+'</g><g class="shipping-art-float"><rect class="shipping-art-paper" x="76" y="8" width="25" height="27" rx="3"/><path d="M81 15h15M81 22h4m5 0h5m-14 6h4m5 0h5"/></g>',
      '<rect class="shipping-art-fill" x="22" y="22" width="57" height="33" rx="5"/><path d="M22 32h57M31 44h10m7 0h7"/><g class="shipping-art-float"><circle class="shipping-art-coin" cx="86" cy="23" r="14"/><path d="M86 15v16m5-13h-7a3 3 0 0 0 0 6h4a3 3 0 0 1 0 6h-7"/></g>',
      '<rect class="shipping-art-fill" x="18" y="44" width="86" height="10" rx="5"/><path d="M25 55v4m72-4v4M32 44V28h19v16m18 0V28h19v16"/><path class="shipping-art-belt" d="M26 49h70"/><g transform="translate(62 17)"><g class="shipping-art-spin"><circle r="9"/><circle r="3"/><path d="M0-14v4m0 20v4M-14 0h4m20 0h4M-10-10l3 3m14 14 3 3M-10 10l3-3M7-7l3-3"/></g></g>',
      '<path d="M20 52h85M27 52v5m71-5v5"/><g class="shipping-art-float"><path class="shipping-art-fill" d="m36 25 24-11 25 11v22L60 58 36 47Z"/><path d="m36 25 24 11 25-11M60 36v22M48 19l25 12v9"/><path class="shipping-art-accent" d="m90 14 3-5m3 12h7m-11 7 5 4"/></g>',
      '<path class="shipping-art-road" d="M16 58h89"/><g class="shipping-art-drive">'+truck+'<path d="m32 30 13-6 13 6v12H32ZM45 25v17"/></g><path class="shipping-art-speed" d="M6 32h10M3 40h12"/>',
      '<path class="shipping-art-fill" d="M19 31 43 12l25 19v24H19Z"/><path d="M12 34 43 9l31 25M35 55V38h16v17M27 29h7v7h-7Z"/><g class="shipping-art-float">'+parcel+'</g>'
    ];
    return '<span class="shipping-step-art" aria-hidden="true"><svg viewBox="0 0 120 68" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><ellipse class="shipping-art-halo" cx="62" cy="35" rx="49" ry="29"/><path class="shipping-art-ground" d="M14 61h94"/>'+scenes[index]+'</svg></span>';
  }
  function workflow(s,q,events) {
    var a=approvals(s), paid=isPaid(s.orders), stopped=['cancelled','payment_failed'].includes(s.orders.status)||s.status==='cancelled';
    var quoted=!!q&&(!!q.accepted_at||new Date(q.expires_at)>new Date());
    var current=!a.buyer?0:!a.factory?1:!quoted?2:3;
    var collected=['collected','departed','arrived','delivered'].includes(s.status);
    var collectionEvent=events.find(function(e){return e.kind==='collected';});
    var delivered=s.status==='delivered';
    var deliveryEvent=events.find(function(e){return e.kind==='delivered';});
    if(paid)current=delivered?8:collected?7:pickupReady(s)?6:productionComplete(s)?5:4;
    var steps=[['المشتري','Buyer','تأكيد الطلب وعنوان التوصيل','Confirm order and delivery address',s.buyer_confirmed_at],
      ['المصنع','Factory','تأكيد عنوان الاستلام والتغليف والوزن','Confirm pickup address, packing and weight',s.factory_confirmed_at],
      ['شركة الشحن','Shipping company','تقييم التكلفة وإصدار العرض — تسجّله الإدارة حاليًا','Price the shipment and submit a quote — entered by the team for now',q&&q.created_at],
      ['المشتري والدفع','Buyer and payment','مراجعة الإجمالي والموافقة ثم سداد المبلغ','Review the total, approve and pay',null],
      ['المصنع — تحت الإنتاج','Factory — in production',s.production_started_at?'إنتاج الطلب ومتابعته حتى اكتماله':'بدء الإنتاج بعد تأكيد الدفع',s.production_started_at?'Produce the order through completion':'Start production after payment confirmation',s.production_completed_at],
      ['المصنع — الشحنة جاهزة','Factory — ready for pickup','تأكيد الجاهزية وإشعار الاستلام — تنسّقه الإدارة حاليًا','Confirm readiness and notify pickup — coordinated by the team for now',s.pickup_ready_at],
      ['شركة الشحن — تم استلام الشحنة','Shipping company — shipment collected','تأكيد استلام الشحنة من المصنع — تسجّله الإدارة حاليًا','Confirm collection from the factory — recorded by the team for now',collectionEvent&&collectionEvent.created_at],
      ['تم تسليم الشحنة للعميل','Shipment delivered to customer','تأكيد التسليم للعميل — تسجّله الإدارة حاليًا','Confirm delivery to the customer — recorded by the team for now',deliveryEvent&&deliveryEvent.created_at]];
    var html='<h2>'+text('مراحل الموافقة على الشحنة','Shipment approval stages')+' · '+esc(s.order_id.slice(0,8))+'</h2><ol class="shipping-steps">';
    html+=steps.map(function(step,i){var state=stopped?'stopped':i<current?'done':i===current?'current':'waiting';return '<li data-step-state="'+state+'"'+(state==='current'?' aria-current="step"':'')+'><span class="shipping-step-number" aria-hidden="true">'+(state==='done'?'✓':i+1)+'</span><div><strong>'+text(step[0],step[1])+'</strong><p>'+text(step[2],step[3])+'</p><small>'+text(state==='done'?'مكتمل':state==='current'?'المرحلة الحالية':state==='stopped'?'متوقف':'بانتظار المرحلة السابقة',state==='done'?'Complete':state==='current'?'Current stage':state==='stopped'?'Stopped':'Waiting for previous stage')+'</small>'+(state==='done'&&step[4]?'<time>'+esc(date(step[4]))+'</time>':'')+'</div>'+stageArt(i)+'</li>';}).join('')+'</ol>';
    var next=stopped?say('الطلب متوقف.','This order is stopped.'):delivered?say('تم تسليم الشحنة للعميل واكتملت جميع المراحل.','The shipment has been delivered to the customer. All stages are complete.'):paid?(pickupReady(s)?(s.pickup_ready_at&&s.status==='booking_requested'?say('أكد المصنع جاهزية الشحنة. أُشعرت الإدارة لتنسيق استلام شركة الشحن.','Factory readiness confirmed. The team has been notified to arrange carrier pickup.'):(collected?say('تم استلام الشحنة من المصنع بواسطة شركة الشحن. تابع تحديثات النقل أدناه.','The shipping company has collected the shipment from the factory. Follow transit updates below.'):say('بانتظار استلام شركة الشحن من المصنع. تسجّل الإدارة التأكيد بعد الاستلام الفعلي.','Awaiting carrier collection from the factory. The team records confirmation after actual collection.'))):!productionComplete(s)?(s.production_started_at?say('الطلب تحت الإنتاج. بعد انتهائه يؤكد المصنع اكتمال الإنتاج ثم جاهزية الشحنة.','The order is in production. The factory confirms completion, then pickup readiness.'):say('تم تأكيد الدفع. الخطوة المطلوبة: يبدأ المصنع الإنتاج.','Payment confirmed. Next: the factory starts production.')):say('اكتمل الإنتاج. الخطوة المطلوبة: يؤكد المصنع أن الشحنة جاهزة للاستلام.','Production completed. Next: the factory confirms pickup readiness.')):
      current===0?say('الخطوة المطلوبة: يؤكد المشتري طلبه وعنوانه لإرساله إلى المصنع.','Next: the buyer confirms the order and address for the factory.'):
      current===1?say('الخطوة المطلوبة: يراجع المصنع عنوان الاستلام ومواصفات الشحنة ويؤكدها.','Next: the factory reviews and confirms pickup and shipment details.'):
      current===2?say('الخطوة المطلوبة: الحصول على عرض شركة الشحن وتسجيله بواسطة الإدارة.','Next: obtain the shipping company quote and have the team record it.'):
      q&&q.accepted_at?say('تم اعتماد الإجمالي. بانتظار سداد المشتري وتأكيد استلام الدفع.','Total approved. Awaiting buyer payment and confirmation of receipt.'):
      say('عرض الشحن جاهز. على المشتري مراجعة السعر والشروط والموافقة قبل الدفع.','Shipping quote ready. The buyer reviews the price and terms and approves before payment.');
    html+='<p class="shipping-next">'+esc(next)+'</p>';
    html+='<details class="shipping-history"><summary>'+text('سجل تحديثات الشحنة','Shipment updates')+' ('+events.length+')</summary><ol class="shipping-timeline">'+events.map(function(e){return '<li>'+esc(label(e.kind))+'<time>'+esc(date(e.created_at))+'</time>'+(e.note?'<p class="shipping-note">'+esc(e.note)+'</p>':'')+'</li>';}).join('')+'</ol></details>';
    return html;
  }
  function packageFields(p,index) {
    return '<fieldset data-package><legend>'+text('مجموعة تغليف','Package group')+' '+(index+1)+'</legend><div class="shipping-fields">'+
      '<label>'+text('نوع التغليف','Package type')+'<select name="type">'+option('carton','كراتين','Cartons',p.type)+option('pallet','طبليات','Pallets',p.type)+'</select></label>'+
      field('count','عدد القطع المتطابقة','Identical package count',p.count||1,'number','required min="1" max="100000" step="1"')+
      ['length_cm','width_cm','height_cm','weight_kg'].map(function(k,i){return field(k,['الطول للقطعة (سم)','العرض للقطعة (سم)','الارتفاع للقطعة (سم)','الوزن بعد التغليف للقطعة (كجم)'][i],['Length per package (cm)','Width per package (cm)','Height per package (cm)','Packed weight per package (kg)'][i],p[k],'number','required min="0.001" max="100000" step="0.001"');}).join('')+
      photosMarkup(p.photos,true)+'</div><button type="button" class="secondary" data-remove-package>'+text('حذف المجموعة','Remove group')+'</button></fieldset>';
  }
  async function loadList(append) {
    if(!append) offset=0;
    var data=await query(root.sb.from('order_shipments').select('*,orders(buyer_id,factory_id,subtotal,payment_fee,vat_amount,total,status,factories(name,owner_id))').order('updated_at',{ascending:false}).order('order_id').range(offset,offset+49));
    rows=append?rows.concat(data):data; offset+=data.length; $('shipping-more').hidden=data.length<50;
    $('shipping-list').innerHTML=rows.length?rows.map(function(s){var f=s.orders&&s.orders.factories;return '<a class="shipment-link" href="?order='+encodeURIComponent(s.order_id)+'" data-shipment="'+esc(s.order_id)+'"'+(selected===s.order_id?' aria-current="page"':'')+'>'+esc(f&&f.name||s.order_id.slice(0,8))+'<small>'+esc(s.order_id.slice(0,8))+' · '+esc(shipmentLabel(s))+'</small></a>';}).join(''):'<p class="shipping-empty">'+text('لا توجد طلبات شحن بعد. أنشئ طلباً من السلة أولاً.','No shipping requests yet. Place an order from the cart first.')+'</p>';
  }
  async function notices() {
    var data=await query(root.sb.from('shipping_notifications').select('id,order_id,kind').is('read_at',null).order('id',{ascending:false}).limit(50));
    $('shipping-notices').innerHTML=data.map(function(n){return '<a href="?order='+encodeURIComponent(n.order_id)+'" data-shipment="'+esc(n.order_id)+'">'+esc(label(n.kind))+' · '+esc(n.order_id.slice(0,8))+'</a>';}).join('');
    return data;
  }
  async function loadDetail(id) {
    if(uploading())return;
    var version=++generation; selected=id;
    $('shipping-workflow').hidden=true;
    $('shipping-detail').innerHTML='<p>'+esc(root.I18N.t('fx_loading'))+'</p>';
    $('shipping-detail').setAttribute('aria-busy','true');
    try {
      var result=await Promise.all([
        query(root.sb.from('order_shipments').select('*,orders(buyer_id,factory_id,subtotal,payment_fee,vat_amount,total,status,factories(name,owner_id))').eq('order_id',id).single()),
        query(root.sb.from('shipping_events').select('id,kind,note,created_at').eq('order_id',id).order('id',{ascending:false}).limit(200)),
        query(root.sb.from('shipping_notifications').select('id').eq('order_id',id).is('read_at',null).order('id',{ascending:false}).limit(1))
      ]);
      var s=result[0], q=s.current_quote_id?await query(root.sb.from('shipping_quotes').select('*').eq('id',s.current_quote_id).single()):null;
      if(version!==generation) return;
      render(s,q,result[1].reverse());
      if(result[2].length) await query(root.sb.rpc('read_shipping_notifications',{p_order_id:id,p_through_id:result[2][0].id}));
      await notices(); if(root.SFShippingNotifications) root.SFShippingNotifications.refresh();
    } catch(err) { if(version===generation) showError(err); }
    finally { if(version===generation) $('shipping-detail').removeAttribute('aria-busy'); }
  }
  function render(s,q,events) {
    var o=s.orders, f=o.factories||{}, buyer=o.buyer_id===root.SF_USER.id, seller=f.owner_id===root.SF_USER.id, admin=!!(root.SF_PROFILE && root.SF_PROFILE.is_admin);
    var editable=['awaiting_details','awaiting_quote','quoted'].includes(s.status)&&o.status==='awaiting_shipping';
    var confirmed=approvals(s);
    $('shipping-workflow').innerHTML=workflow(s,q,events); $('shipping-workflow').hidden=false;
    var d=s.destination||{}, p=s.packing||{}, html='<h2>'+text('طلب','Order')+' '+esc(s.order_id.slice(0,8))+'</h2><span class="shipping-badge">'+esc(shipmentLabel(s))+'</span>';
    if(s.status==='booking_requested'&&isPaid(o)&&!productionComplete(s)&&seller)html+='<section class="shipping-payment"><h3>'+text('مرحلة الإنتاج','Production stage')+'</h3><p>'+text(s.production_started_at?'الطلب تحت الإنتاج. أكد انتهاء الإنتاج عندما تكتمل البضاعة.':'تم تأكيد الدفع. يمكنك الآن تأكيد بدء إنتاج الطلب.',s.production_started_at?'The order is in production. Confirm completion when the goods are produced.':'Payment confirmed. You can now start production.')+'</p>'+(s.production_started_at?'<p>'+text('بدأ الإنتاج: ','Production started: ')+esc(date(s.production_started_at))+'</p>':'')+'<button type="button" data-action="'+(s.production_started_at?'production_complete':'production_start')+'">'+(s.production_started_at?text('تأكيد انتهاء الإنتاج','Confirm production completion'):text('بدء الإنتاج','Start production'))+'</button></section>';
    if(s.status==='booking_requested'&&isPaid(o)&&productionComplete(s)&&!pickupReady(s)&&seller)html+='<section class="shipping-payment"><h3>'+text('تأكيد جاهزية الشحنة للاستلام','Confirm pickup readiness')+'</h3><p>'+text('أكد أن البضاعة معبأة وجاهزة في عنوان الاستلام المتفق عليه. سيصل إشعار للإدارة لتنسيق الاستلام مع شركة الشحن.','Confirm the packed goods are ready at the agreed pickup address. The team will be notified to arrange carrier pickup.')+'</p><button type="button" data-action="pickup_ready">'+text('الشحنة جاهزة — إشعار الاستلام','Shipment ready — notify pickup')+'</button></section>';
    html+='<dl class="shipping-summary">'+line('المصنع','Factory',f.name||'—')+line('المنتجات','Products',money(o.subtotal))+line('رسوم المنصة','Platform fee',money(o.payment_fee))+line('ضريبة المنتجات والرسوم','Products and fee VAT',money(o.vat_amount))+
      line('الشحن شاملاً رسومه وضرائبه','Shipping including its fees and taxes',q&&q.accepted_at?money(q.total):say('بانتظار عرض الشحن والموافقة عليه','Pending shipping quote and acceptance'))+
      line(o.status==='awaiting_shipping'?'إجمالي المنتجات قبل الشحن':'الإجمالي المعتمد',o.status==='awaiting_shipping'?'Products total before shipping':'Confirmed total',money(o.total),true)+'</dl>';
    if(s.destination) html+='<h3>'+text('الوجهة','Destination')+'</h3><p class="shipping-note">'+esc([d.contact,d.phone_country_code,d.phone,d.address,d.city,d.country,d.postal_code,s.delivery_type==='port'?say('إلى الميناء: ','To port: ')+(d.port||''):say('إلى الباب','To door'),d.delivery_notes].filter(Boolean).join(' · '))+'</p>';
    if(s.packing) {
      html+='<h3>'+text('الاستلام والتغليف','Pickup and packing')+'</h3><p class="shipping-note">'+esc([p.pickup_address,p.contact,p.phone,date(s.ready_at),p.refrigerated?say('يحتاج تبريداً','Refrigerated'):say('دون تبريد','Not refrigerated'),p.special_requirements].filter(Boolean).join(' · '))+'</p>';
      html+='<ul>'+p.packages.map(function(x){return '<li>'+esc(x.count+' × '+(x.type==='carton'?say('كرتون','carton'):say('طبلية','pallet'))+' · '+x.length_cm+' × '+x.width_cm+' × '+x.height_cm+' cm · '+x.weight_kg+' kg / '+say('قطعة','package'))+(x.photos&&x.photos.length?photosMarkup(x.photos,false):'')+'</li>';}).join('')+'</ul>';
    }
    if(q) {
      var expired=new Date(q.expires_at)<=new Date();
      html+='<h3>'+text('عرض شركة الشحن','Carrier quote')+'</h3><dl class="shipping-summary">'+line('الشركة ومرجع عرضها','Carrier and quote reference',q.carrier+' · '+q.carrier_quote_reference)+
        line('أجرة النقل','Freight',money(q.freight))+line('رسوم إضافية','Additional fees',money(q.additional_fees))+line('ضرائب الشحن','Shipping taxes',money(q.taxes))+line('إجمالي الشحن','Shipping total',money(q.total),true)+
        line('التوصيل المتوقع بعد الاستلام','Estimated delivery after pickup',q.estimated_days_min+'–'+q.estimated_days_max+' '+say('يوماً','days'))+line('صالح حتى','Valid until',date(q.expires_at))+line('يشمل','Includes',q.inclusions)+line('لا يشمل / رسوم لاحقة','Excludes / later charges',q.exclusions)+'</dl>';
      if(s.status==='quoted') {
        html+='<p class="shipping-note">'+text('التقدير النهائي: ','Final estimate: ')+esc(money(Number(o.total)+Number(q.total)))+'</p>';
        if(expired) html+='<p>'+text('انتهت صلاحية هذا العرض. يلزم عرض جديد.','This quote expired. A new quote is required.')+'</p>';
        if(buyer) html+='<div class="shipping-actions">'+(!expired?'<button data-action="accept">'+text('أوافق على الإجمالي وأتابع للدفع','Approve total and proceed to payment')+'</button>':'')+'<button class="secondary" data-action="decline">'+text('طلب عرض بديل','Request replacement quote')+'</button></div>';
      }
    }
    if(s.booking_reference) html+='<h3>'+text('الحجز المؤكد','Confirmed booking')+'</h3><dl class="shipping-summary">'+line('رقم حجز الشركة','Carrier booking reference',s.booking_reference)+line('موعد الاستلام','Pickup time',date(s.pickup_at))+'</dl>';
    if(o.status==='awaiting_payment')html+='<section class="shipping-payment"><h3>'+text('بانتظار الدفع','Awaiting payment')+'</h3><p>'+text('الإجمالي المعتمد: ','Approved total: ')+esc(money(o.total))+'</p><p>'+text('الدفع حاليًا بالتنسيق مع المصنع خارج المنصة. بعد السداد يؤكد المصنع أو الإدارة استلام المبلغ؛ لا تُعد الموافقة على العرض دفعًا.','Payment is currently arranged with the factory outside the platform. After payment, the factory or team confirms receipt; accepting the quote does not record payment.')+'</p><a href="web-orders.html">'+text('فتح الطلبات لمتابعة الدفع','Open orders to follow up on payment')+'</a></section>';
    if(o.status==='awaiting_payment'&&(seller||admin))html+='<button type="button" data-action="payment">'+text('تأكيد استلام المبلغ فعليًا','Confirm actual payment receipt')+'</button>';
    if(s.status==='booking_requested'&&isPaid(o)&&productionComplete(s)) html+='<p class="shipping-note">'+(pickupReady(s)?text('الشحنة جاهزة. بانتظار تنسيق الاستلام وتأكيد الحجز لدى شركة الشحن.','Shipment ready. Awaiting pickup coordination and carrier booking confirmation.'):text('تم الدفع. بانتظار تأكيد المصنع لجاهزية الشحنة قبل تنسيق الاستلام.','Payment confirmed. Awaiting factory readiness before arranging pickup.'))+'</p>';
    if(editable) html+='<p class="shipping-note">'+text('تغيير الوجهة يعيد الطلب إلى المصنع للتأكيد. تغيير الوجهة أو التغليف يُلغي عرض الشحن السابق.','Changing the destination returns the request to the factory for confirmation. Destination or packing changes invalidate the previous quote.')+'</p>';
    if(editable&&buyer) html+=form('destination',text('وجهة الشحنة','Shipment destination'),destinationChoice(destinationScope(d))+
      '<p class="shipping-note wide" role="status" data-domestic-note'+(destinationScope(d)==='domestic'?'':' hidden')+'>'+text('سيُستخدم عنوان التوصيل السعودي المحفوظ.','Your saved Saudi delivery address will be used.')+'</p>'+
      '<button type="button" class="secondary wide" data-use-saved-address hidden>'+text('استخدام العنوان المحفوظ في حسابي','Use the saved address in my account')+'</button>'+
      '<a class="wide" href="web-addresses.html">'+text('إدارة عناوين التوصيل','Manage delivery addresses')+'</a>'+
      '<fieldset class="shipping-fields shipping-destination-fields wide" data-destination-fields'+(destinationScope(d)==='international'?'':' hidden disabled')+'><legend>'+text('تفاصيل التوصيل خارج السعودية','Delivery details outside Saudi Arabia')+'</legend>'+
      field('country','الدولة','Country',d.country)+field('city','المدينة','City',d.city)+field('contact','اسم المستلم','Recipient name',d.contact)+field('phone','هاتف المستلم مع رمز الدولة','Recipient phone with country code',d.phone,'tel','required maxlength="60"')+
      field('postal_code','الرمز البريدي (اختياري)','Postal code (optional)',d.postal_code,'text','maxlength="30"')+'<label>'+text('نوع التوصيل','Delivery service')+'<select name="delivery_type">'+option('door','إلى الباب','To door',s.delivery_type)+option('port','إلى الميناء','To port',s.delivery_type)+'</select></label>'+
      field('port','اسم الميناء (للتوصيل إلى الميناء)','Port name (for delivery to port)',d.port,'text','maxlength="200"')+area('address','العنوان الكامل / عنوان المستودع','Full address / warehouse address',d.address,1000)+'</fieldset>',text('احسب الشحن — طلب عرض يدوي','Calculate shipping — request manual quote'));
    if(editable&&seller&&!confirmed.buyer)html+='<p class="shipping-note">'+text('بانتظار تأكيد المشتري لطلبه وعنوانه قبل إدخال بيانات المصنع.','Awaiting buyer order and address confirmation before factory details.')+'</p>';
    if(editable&&seller&&confirmed.buyer) html+=form('packing',text('بيانات شحنة المصنع','Factory shipment details'),area('pickup_address','عنوان الاستلام الكامل','Full pickup address',p.pickup_address,1500)+field('contact','اسم مسؤول الاستلام','Pickup contact',p.contact)+field('phone','هاتف مسؤول الاستلام','Pickup phone',p.phone,'tel','required maxlength="60"')+
      field('ready_at','موعد الجاهزية (بتوقيت جهازك)','Ready for pickup (your local time)',localDate(s.ready_at),'datetime-local','required')+
      '<label><input name="refrigerated" type="checkbox"'+(p.refrigerated?' checked':'')+'>'+text('تحتاج تبريداً','Requires refrigeration')+'</label>'+area('special_requirements','نوع الحاوية والمتطلبات الخاصة (اكتب لا يوجد إن لم تلزم)','Container and special requirements (write none if not needed)',p.special_requirements||say('لا يوجد','None'),2000)+
      '<div class="wide" id="shipping-packages">'+(p.packages||[{}]).map(packageFields).join('')+'</div><button type="button" class="secondary" id="shipping-add-package">'+text('إضافة مقاس تغليف آخر','Add another package size')+'</button>',text('تأكيد بيانات الشحنة وإرسالها للتسعير','Confirm shipment details and send for pricing'));
    if(admin&&confirmed.buyer&&confirmed.factory&&['awaiting_quote','quoted'].includes(s.status)) html+=form('quote',text('إدخال عرض شركة الشحن','Enter carrier quote'),field('carrier','اسم شركة الشحن','Carrier name','')+field('carrier_quote_reference','مرجع عرض الشركة','Carrier quote reference','','text','required maxlength="200"')+
      field('freight','أجرة النقل (SAR)','Freight (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+field('additional_fees','الرسوم الإضافية (SAR)','Additional fees (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+field('taxes','ضرائب الشحن (SAR)','Shipping taxes (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+
      field('estimated_days_min','أقل مدة بعد الاستلام (أيام)','Minimum transit days',1,'number','required min="1" max="365" step="1"')+field('estimated_days_max','أقصى مدة بعد الاستلام (أيام)','Maximum transit days',7,'number','required min="1" max="365" step="1"')+field('expires_at','صلاحية العرض (بتوقيت جهازك)','Quote expiry (your local time)','','datetime-local','required')+
      area('inclusions','ما يشمله السعر: التخليص والرسوم والتوصيل','Included: customs clearance, fees and delivery','')+area('exclusions','ما لا يشمله / مبالغ لاحقة ومن يتحملها','Excluded / later charges and who pays them',''),text('نشر العرض وإشعار العميل','Publish quote and notify buyer'));
    if(admin&&s.status==='booking_requested'&&isPaid(o)&&pickupReady(s)) html+=form('book',text('تأكيد الحجز لدى الشركة','Confirm booking with carrier'),field('booking_reference','مرجع الحجز المؤكد من الشركة','Confirmed carrier booking reference','','text','required maxlength="200"')+field('pickup_at','موعد الاستلام المؤكد (بتوقيت جهازك)','Confirmed pickup (your local time)',localDate(s.ready_at),'datetime-local','required'),text('حفظ الحجز المؤكد','Save confirmed booking'));
    var next={booked:'collected',collected:'departed',departed:'arrived',arrived:'delivered'}[s.status];
    if(admin&&next) html+=form('track',next==='collected'?text('تأكيد استلام شركة الشحن من المصنع','Confirm carrier collection from factory'):next==='delivered'?text('تأكيد تسليم الشحنة للعميل','Confirm shipment delivery to customer'):text('تسجيل تحديث من شركة الشحن','Record carrier update'),'<p class="wide">'+esc(label(next))+'</p>'+area('note','تفاصيل التحديث الوارد من الشركة','Update received from carrier',''),next==='collected'?text('تأكيد: تم استلام الشحنة','Confirm: shipment collected'):next==='delivered'?text('تأكيد: تم تسليم الشحنة للعميل','Confirm: shipment delivered to customer'):text('تسجيل التحديث','Record update'));
    if(editable&&buyer) html+='<div class="shipping-actions"><button class="secondary" data-action="cancel">'+text('إلغاء الطلب قبل اعتماد الشحن','Cancel order before accepting shipping')+'</button></div>';
    $('shipping-detail').innerHTML=html;
    if(root.SFShippingImages)root.SFShippingImages.bind($('shipping-detail'),s.order_id);
    $('shipping-detail').querySelectorAll('form[data-action="destination"]').forEach(function(el){
      syncDestinationScope(el);
      el.addEventListener('input',function(){syncDestinationScope(el);});
      el.addEventListener('change',function(){syncDestinationScope(el);if(el.elements.destination_scope.value==='domestic')loadDomesticDestination(el,s);});
      el.querySelector('[data-use-saved-address]').addEventListener('click',function(){ $('shipping-error').hidden=true; loadDomesticDestination(el,s,true); });
      if(el.elements.destination_scope.value==='domestic')loadDomesticDestination(el,s);
    });
    $('shipping-detail').querySelectorAll('form').forEach(function(el){el.addEventListener('submit',function(event){event.preventDefault(); if(uploading()||!el.reportValidity())return; var data=Object.fromEntries(new FormData(el)); var action=el.dataset.action;
      if(action==='destination') {
        if(data.destination_scope==='domestic') {
          if(el._domesticLoading)return;
          if(!el._domesticDestination){showError({message:'shipping_saved_address_missing'});return;}
          action=el._useSavedAddress?'saved_destination':'domestic_destination';data={expected_destination:el._domesticDestination};
        } else {
          if(data.destination_scope!=='international')return;
          data={destination:{scope:'international',country:data.country,city:data.city,address:data.address,contact:data.contact,phone:data.phone,postal_code:data.postal_code,port:data.port},delivery_type:data.delivery_type};
        }
      }
      if(action==='packing'&&!root.SFShippingImages){showError({message:'shipping_images_unavailable'});return;}
      if(action==='packing') data={ready_at:new Date(data.ready_at).toISOString(),packing:{pickup_address:data.pickup_address,contact:data.contact,phone:data.phone,refrigerated:el.elements.refrigerated.checked,special_requirements:data.special_requirements,packages:Array.from(el.querySelectorAll('[data-package]')).map(function(group){var x={};group.querySelectorAll('input[name],select[name]').forEach(function(input){x[input.name]=input.name==='type'?input.value:Number(input.value);});var photos=group.querySelector('[data-shipping-photos]');if(photos&&root.SFShippingImages)x.photos=root.SFShippingImages.paths(photos);return x;})}};
      if(action==='quote') { ['freight','additional_fees','taxes','estimated_days_min','estimated_days_max'].forEach(function(k){data[k]=Number(data[k]);});data.expires_at=new Date(data.expires_at).toISOString(); }
      if(action==='book') data.pickup_at=new Date(data.pickup_at).toISOString();
      if(action==='track') {
        if(next==='collected'&&!root.confirm(say('هل أكدت شركة الشحن استلام البضاعة فعليًا من المصنع؟','Has the carrier confirmed actual collection of the goods from the factory?')))return;
        if(next==='delivered'&&!root.confirm(say('هل أكدت شركة الشحن تسليم البضاعة فعليًا للعميل؟','Has the carrier confirmed actual delivery of the goods to the customer?')))return;
        data.status=next;
      }
      act(s,action,data);
    });});
    $('shipping-detail').querySelectorAll('button[data-action]').forEach(function(el){el.addEventListener('click',function(){var action=el.dataset.action;if(action==='accept'&&!root.confirm(say('تأكيد الموافقة على إجمالي الطلب شاملاً الشحن ','Approve order total including shipping ')+money(Number(o.total)+Number(q.total))+say(' والشروط المعروضة والانتقال إلى الدفع؟',' and the displayed terms, and proceed to payment?')))return;if(action==='production_start'&&!root.confirm(say('تأكيد بدء إنتاج الطلب؟','Confirm production start?')))return;if(action==='production_complete'&&!root.confirm(say('هل اكتمل إنتاج البضاعة؟','Has production of the goods been completed?')))return;if(action==='pickup_ready'&&!root.confirm(say('هل البضاعة معبأة وجاهزة للاستلام؟ سيصل إشعار للإدارة لتنسيق الاستلام.','Are the goods packed and ready for pickup? The team will be notified to arrange collection.')))return;if(action==='payment'&&!root.confirm(say('هل استلمت فعليًا كامل مبلغ الطلب: ','Have you actually received the full order amount: ')+money(o.total)+'؟'))return;if(action==='cancel'&&!root.confirm(say('تأكيد إلغاء الطلب؟','Cancel this order?')))return;act(s,action,{quote_id:q&&q.id});});});
    var add=$('shipping-add-package'); if(add) add.addEventListener('click',function(){var host=$('shipping-packages');if(!uploading()&&host.children.length<50){host.insertAdjacentHTML('beforeend',packageFields({},host.children.length));if(root.SFShippingImages)root.SFShippingImages.bind($('shipping-detail'),s.order_id,true);}});
    var packages=$('shipping-packages');if(packages)packages.addEventListener('click',function(e){var btn=e.target.closest('[data-remove-package]');if(btn&&!uploading()&&packages.children.length>1)btn.closest('fieldset').remove();});
  }
  async function act(s,action,data) {
    if(busy||uploading())return; busy=true; $('shipping-error').hidden=true;
    $('shipping-detail').querySelectorAll('button,input,select,textarea').forEach(function(el){el.disabled=true;});
    try {
      data.revision=s.revision;
      if(action==='domestic_destination'||action==='saved_destination')await query(root.sb.rpc(action==='saved_destination'?'link_saved_shipping_address':'set_domestic_shipping_destination',{p_order_id:s.order_id,p_revision:s.revision,p_expected_destination:data.expected_destination}));
      else if(action==='payment')await query(root.sb.rpc('mark_order_paid',{p_order_id:s.order_id}));
      else if(action==='production_start'||action==='production_complete')await query(root.sb.rpc('update_shipping_production',{p_order_id:s.order_id,p_revision:s.revision,p_action:action==='production_start'?'start':'complete'}));
      else if(action==='pickup_ready')await query(root.sb.rpc('confirm_shipping_pickup_ready',{p_order_id:s.order_id,p_revision:s.revision}));
      else await query(root.sb.rpc('update_manual_shipping',{p_order_id:s.order_id,p_action:action,p_payload:data}));
      await loadList(false);await loadDetail(s.order_id);
    }
    catch(err){showError(err);}
    finally{busy=false;$('shipping-detail').querySelectorAll('button,input,select,textarea').forEach(function(el){el.disabled=false;});$('shipping-detail').querySelectorAll('form[data-action="destination"]').forEach(syncDestinationScope);}
  }
  document.addEventListener('click',function(e){var link=e.target.closest('[data-shipment]');if(!link)return;e.preventDefault();if(busy||uploading())return;history.replaceState(null,'','?order='+encodeURIComponent(link.dataset.shipment));$('shipping-error').hidden=true;loadDetail(link.dataset.shipment);});
  $('shipping-refresh').addEventListener('click',function(){if(busy)return; $('shipping-error').hidden=true;loadList(false).then(function(){return selected?loadDetail(selected):notices();}).catch(showError);});
  $('shipping-more').addEventListener('click',function(){loadList(true).catch(showError);});
  root.SF_AUTH_READY.then(async function(){if(!root.SF_USER)return;await loadList(false);await notices();var id=new URLSearchParams(location.search).get('order')||(rows[0]&&rows[0].order_id);if(id)await loadDetail(id);else $('shipping-detail').innerHTML='<p class="shipping-empty">'+text('اختر طلب الشحن لعرض بياناته.','Select a shipment to see its details.')+'</p>';}).catch(showError);
})(window);
