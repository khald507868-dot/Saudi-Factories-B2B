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
    destination:['تم تحديث الوجهة وطلب التسعير','Destination submitted for pricing'],packing:['تم تحديث التغليف','Packing updated'],quote:['عرض شحن جديد','New shipping quote'],
    accept:['وافق العميل؛ طُلب الحجز','Buyer accepted; booking requested'],decline:['طُلب عرض بديل','Replacement quote requested'],book:['تأكيد حجز الشركة','Carrier booking confirmed'],cancel:['أُلغي الطلب','Order cancelled'],packing_needed:['طلب جديد يحتاج بيانات التغليف','New order needs packing details']
  };
  function label(key) { var pair=states[key]; return pair?say(pair[0],pair[1]):key; }
  async function query(job) { var r=await job; if(r.error) throw r.error; return r.data; }
  function showError(err) {
    var msg=err && err.message || String(err), key=msg.match(/shipping_[a-z_]+/);
    var map={shipping_stale:['تغيّرت بيانات الطلب. حدّث الصفحة وراجع العرض قبل المحاولة.','The request changed. Refresh and review it before retrying.'],
      shipping_quote_expired:['انتهت صلاحية العرض. اطلب عرضاً بديلاً.','This quote expired. Request a replacement.'],
      shipping_access_denied:['لا يملك هذا الحساب صلاحية هذا الإجراء.','This account cannot perform this action.'],
      shipping_locked:['لا يمكن تعديل البيانات في هذه المرحلة.','These details are locked at this stage.'],
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
  function form(action,title,fields,button) { return '<form data-action="'+action+'"><h3>'+title+'</h3><div class="shipping-fields">'+fields+'</div><button type="submit">'+button+'</button></form>'; }
  function line(ar,en,value,isTotal) { return '<div'+(isTotal?' class="total"':'')+'><dt>'+text(ar,en)+'</dt><dd>'+esc(value)+'</dd></div>'; }
  function packageFields(p,index) {
    return '<fieldset data-package><legend>'+text('مجموعة تغليف','Package group')+' '+(index+1)+'</legend><div class="shipping-fields">'+
      '<label>'+text('نوع التغليف','Package type')+'<select name="type">'+option('carton','كراتين','Cartons',p.type)+option('pallet','طبليات','Pallets',p.type)+'</select></label>'+
      field('count','عدد القطع المتطابقة','Identical package count',p.count||1,'number','required min="1" max="100000" step="1"')+
      ['length_cm','width_cm','height_cm','weight_kg'].map(function(k,i){return field(k,['الطول للقطعة (سم)','العرض للقطعة (سم)','الارتفاع للقطعة (سم)','الوزن بعد التغليف للقطعة (كجم)'][i],['Length per package (cm)','Width per package (cm)','Height per package (cm)','Packed weight per package (kg)'][i],p[k],'number','required min="0.001" max="100000" step="0.001"');}).join('')+
      '</div><button type="button" class="secondary" data-remove-package>'+text('حذف المجموعة','Remove group')+'</button></fieldset>';
  }
  async function loadList(append) {
    if(!append) offset=0;
    var data=await query(root.sb.from('order_shipments').select('*,orders(buyer_id,factory_id,subtotal,payment_fee,vat_amount,total,status,factories(name,owner_id))').order('updated_at',{ascending:false}).order('order_id').range(offset,offset+49));
    rows=append?rows.concat(data):data; offset+=data.length; $('shipping-more').hidden=data.length<50;
    $('shipping-list').innerHTML=rows.length?rows.map(function(s){var f=s.orders&&s.orders.factories;return '<a class="shipment-link" href="?order='+encodeURIComponent(s.order_id)+'" data-shipment="'+esc(s.order_id)+'"'+(selected===s.order_id?' aria-current="page"':'')+'>'+esc(f&&f.name||s.order_id.slice(0,8))+'<small>'+esc(s.order_id.slice(0,8))+' · '+esc(label(s.status))+'</small></a>';}).join(''):'<p class="shipping-empty">'+text('لا توجد طلبات شحن بعد. أنشئ طلباً من السلة أولاً.','No shipping requests yet. Place an order from the cart first.')+'</p>';
  }
  async function notices() {
    var data=await query(root.sb.from('shipping_notifications').select('id,order_id,kind').is('read_at',null).order('id',{ascending:false}).limit(50));
    $('shipping-notices').innerHTML=data.map(function(n){return '<a href="?order='+encodeURIComponent(n.order_id)+'" data-shipment="'+esc(n.order_id)+'">'+esc(label(n.kind))+' · '+esc(n.order_id.slice(0,8))+'</a>';}).join('');
    return data;
  }
  async function loadDetail(id) {
    var version=++generation; selected=id;
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
    var d=s.destination||{}, p=s.packing||{}, html='<h2>'+text('طلب','Order')+' '+esc(s.order_id.slice(0,8))+'</h2><span class="shipping-badge">'+esc(label(s.status))+'</span>';
    html+='<dl class="shipping-summary">'+line('المصنع','Factory',f.name||'—')+line('المنتجات','Products',money(o.subtotal))+line('رسوم المنصة','Platform fee',money(o.payment_fee))+line('ضريبة المنتجات والرسوم','Products and fee VAT',money(o.vat_amount))+
      line('الشحن شاملاً رسومه وضرائبه','Shipping including its fees and taxes',q&&q.accepted_at?money(q.total):say('بانتظار عرض الشحن والموافقة عليه','Pending shipping quote and acceptance'))+
      line(o.status==='awaiting_shipping'?'إجمالي المنتجات قبل الشحن':'الإجمالي المعتمد',o.status==='awaiting_shipping'?'Products total before shipping':'Confirmed total',money(o.total),true)+'</dl>';
    if(s.destination) html+='<h3>'+text('الوجهة','Destination')+'</h3><p class="shipping-note">'+esc([d.contact,d.phone,d.address,d.city,d.country,d.postal_code,s.delivery_type==='port'?say('إلى الميناء: ','To port: ')+(d.port||''):say('إلى الباب','To door')].filter(Boolean).join(' · '))+'</p>';
    if(s.packing) {
      html+='<h3>'+text('الاستلام والتغليف','Pickup and packing')+'</h3><p class="shipping-note">'+esc([p.pickup_address,p.contact,p.phone,date(s.ready_at),p.refrigerated?say('يحتاج تبريداً','Refrigerated'):say('دون تبريد','Not refrigerated'),p.special_requirements].filter(Boolean).join(' · '))+'</p>';
      html+='<ul>'+p.packages.map(function(x){return '<li>'+esc(x.count+' × '+(x.type==='carton'?say('كرتون','carton'):say('طبلية','pallet'))+' · '+x.length_cm+' × '+x.width_cm+' × '+x.height_cm+' cm · '+x.weight_kg+' kg / '+say('قطعة','package'))+'</li>';}).join('')+'</ul>';
    }
    if(q) {
      var expired=new Date(q.expires_at)<=new Date();
      html+='<h3>'+text('عرض شركة الشحن','Carrier quote')+'</h3><dl class="shipping-summary">'+line('الشركة ومرجع عرضها','Carrier and quote reference',q.carrier+' · '+q.carrier_quote_reference)+
        line('أجرة النقل','Freight',money(q.freight))+line('رسوم إضافية','Additional fees',money(q.additional_fees))+line('ضرائب الشحن','Shipping taxes',money(q.taxes))+line('إجمالي الشحن','Shipping total',money(q.total),true)+
        line('التوصيل المتوقع بعد الاستلام','Estimated delivery after pickup',q.estimated_days_min+'–'+q.estimated_days_max+' '+say('يوماً','days'))+line('صالح حتى','Valid until',date(q.expires_at))+line('يشمل','Includes',q.inclusions)+line('لا يشمل / رسوم لاحقة','Excludes / later charges',q.exclusions)+'</dl>';
      if(s.status==='quoted') {
        html+='<p class="shipping-note">'+text('التقدير النهائي: ','Final estimate: ')+esc(money(Number(o.total)+Number(q.total)))+'</p>';
        if(expired) html+='<p>'+text('انتهت صلاحية هذا العرض. يلزم عرض جديد.','This quote expired. A new quote is required.')+'</p>';
        if(buyer) html+='<div class="shipping-actions">'+(!expired?'<button data-action="accept">'+text('أوافق على السعر والشروط وأطلب الحجز','Accept price and terms; request booking')+'</button>':'')+'<button class="secondary" data-action="decline">'+text('طلب عرض بديل','Request replacement quote')+'</button></div>';
      }
    }
    if(s.booking_reference) html+='<h3>'+text('الحجز المؤكد','Confirmed booking')+'</h3><dl class="shipping-summary">'+line('رقم حجز الشركة','Carrier booking reference',s.booking_reference)+line('موعد الاستلام','Pickup time',date(s.pickup_at))+'</dl>';
    if(s.status==='booking_requested') html+='<p class="shipping-note">'+text('تمت الموافقة على السعر وطلب الحجز. ننتظر تأكيد شركة الشحن ومرجع الحجز.','Price accepted and booking requested. Awaiting carrier confirmation and booking reference.')+'</p>';
    if(editable) html+='<p class="shipping-note">'+text('تعديل الوجهة أو التغليف يُلغي صلاحية العرض الحالي ويطلب تسعيره من جديد.','Changing the destination or packing invalidates the current quote and requests new pricing.')+'</p>';
    if(editable&&buyer) html+=form('destination',text('وجهة الشحنة','Shipment destination'),
      field('country','الدولة','Country',d.country)+field('city','المدينة','City',d.city)+field('contact','اسم المستلم','Recipient name',d.contact)+field('phone','هاتف المستلم مع رمز الدولة','Recipient phone with country code',d.phone,'tel','required maxlength="60"')+
      field('postal_code','الرمز البريدي (اختياري)','Postal code (optional)',d.postal_code,'text','maxlength="30"')+'<label>'+text('نوع التوصيل','Delivery service')+'<select name="delivery_type">'+option('door','إلى الباب','To door',s.delivery_type)+option('port','إلى الميناء','To port',s.delivery_type)+'</select></label>'+
      field('port','اسم الميناء (للتوصيل إلى الميناء)','Port name (for delivery to port)',d.port,'text','maxlength="200"')+area('address','العنوان الكامل / عنوان المستودع','Full address / warehouse address',d.address,1000),text('احسب الشحن — طلب عرض يدوي','Calculate shipping — request manual quote'));
    if(editable&&seller) html+=form('packing',text('بيانات شحنة المصنع','Factory shipment details'),area('pickup_address','عنوان الاستلام الكامل','Full pickup address',p.pickup_address,1500)+field('contact','اسم مسؤول الاستلام','Pickup contact',p.contact)+field('phone','هاتف مسؤول الاستلام','Pickup phone',p.phone,'tel','required maxlength="60"')+
      field('ready_at','موعد الجاهزية (بتوقيت جهازك)','Ready for pickup (your local time)',localDate(s.ready_at),'datetime-local','required')+
      '<label><input name="refrigerated" type="checkbox"'+(p.refrigerated?' checked':'')+'>'+text('تحتاج تبريداً','Requires refrigeration')+'</label>'+area('special_requirements','نوع الحاوية والمتطلبات الخاصة (اكتب لا يوجد إن لم تلزم)','Container and special requirements (write none if not needed)',p.special_requirements||say('لا يوجد','None'),2000)+
      '<div class="wide" id="shipping-packages">'+(p.packages||[{}]).map(packageFields).join('')+'</div><button type="button" class="secondary" id="shipping-add-package">'+text('إضافة مقاس تغليف آخر','Add another package size')+'</button>',text('حفظ بيانات الشحنة','Save packing details'));
    if(admin&&['awaiting_quote','quoted'].includes(s.status)) html+=form('quote',text('إدخال عرض شركة الشحن','Enter carrier quote'),field('carrier','اسم شركة الشحن','Carrier name','')+field('carrier_quote_reference','مرجع عرض الشركة','Carrier quote reference','','text','required maxlength="200"')+
      field('freight','أجرة النقل (SAR)','Freight (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+field('additional_fees','الرسوم الإضافية (SAR)','Additional fees (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+field('taxes','ضرائب الشحن (SAR)','Shipping taxes (SAR)',0,'number','required min="0" max="1000000000" step="0.01"')+
      field('estimated_days_min','أقل مدة بعد الاستلام (أيام)','Minimum transit days',1,'number','required min="1" max="365" step="1"')+field('estimated_days_max','أقصى مدة بعد الاستلام (أيام)','Maximum transit days',7,'number','required min="1" max="365" step="1"')+field('expires_at','صلاحية العرض (بتوقيت جهازك)','Quote expiry (your local time)','','datetime-local','required')+
      area('inclusions','ما يشمله السعر: التخليص والرسوم والتوصيل','Included: customs clearance, fees and delivery','')+area('exclusions','ما لا يشمله / مبالغ لاحقة ومن يتحملها','Excluded / later charges and who pays them',''),text('نشر العرض وإشعار العميل','Publish quote and notify buyer'));
    if(admin&&s.status==='booking_requested') html+=form('book',text('تأكيد الحجز لدى الشركة','Confirm booking with carrier'),field('booking_reference','مرجع الحجز المؤكد من الشركة','Confirmed carrier booking reference','','text','required maxlength="200"')+field('pickup_at','موعد الاستلام المؤكد (بتوقيت جهازك)','Confirmed pickup (your local time)',localDate(s.ready_at),'datetime-local','required'),text('حفظ الحجز المؤكد','Save confirmed booking'));
    var next={booked:'collected',collected:'departed',departed:'arrived',arrived:'delivered'}[s.status];
    if(admin&&next) html+=form('track',text('تسجيل تحديث من شركة الشحن','Record carrier update'),'<p class="wide">'+esc(label(next))+'</p>'+area('note','تفاصيل التحديث الوارد من الشركة','Update received from carrier',''),text('تسجيل التحديث','Record update'));
    if(editable&&buyer) html+='<div class="shipping-actions"><button class="secondary" data-action="cancel">'+text('إلغاء الطلب قبل اعتماد الشحن','Cancel order before accepting shipping')+'</button></div>';
    html+='<h3>'+text('سجل تحديثات الشحنة','Shipment updates')+'</h3><p class="shipping-note">'+text('تسجل الإدارة التحديثات التي ترد من الشركة. هذا سجل حالات وليس موقعاً مباشراً على الخريطة.','The team records updates received from the carrier. These are shipment statuses, not a live map.')+'</p><ol class="shipping-timeline">'+events.map(function(e){return '<li>'+esc(label(e.kind))+'<time>'+esc(date(e.created_at))+'</time>'+(e.note?'<p class="shipping-note">'+esc(e.note)+'</p>':'')+'</li>';}).join('')+'</ol>';
    $('shipping-detail').innerHTML=html;
    $('shipping-detail').querySelectorAll('form').forEach(function(el){el.addEventListener('submit',function(event){event.preventDefault(); if(!el.reportValidity())return; var data=Object.fromEntries(new FormData(el)); var action=el.dataset.action;
      if(action==='destination') data={destination:{country:data.country,city:data.city,address:data.address,contact:data.contact,phone:data.phone,postal_code:data.postal_code,port:data.port},delivery_type:data.delivery_type};
      if(action==='packing') data={ready_at:new Date(data.ready_at).toISOString(),packing:{pickup_address:data.pickup_address,contact:data.contact,phone:data.phone,refrigerated:el.elements.refrigerated.checked,special_requirements:data.special_requirements,packages:Array.from(el.querySelectorAll('[data-package]')).map(function(group){var x={};group.querySelectorAll('input,select').forEach(function(input){x[input.name]=input.name==='type'?input.value:Number(input.value);});return x;})}};
      if(action==='quote') { ['freight','additional_fees','taxes','estimated_days_min','estimated_days_max'].forEach(function(k){data[k]=Number(data[k]);});data.expires_at=new Date(data.expires_at).toISOString(); }
      if(action==='book') data.pickup_at=new Date(data.pickup_at).toISOString();
      if(action==='track') data.status=next;
      act(s,action,data);
    });});
    $('shipping-detail').querySelectorAll('button[data-action]').forEach(function(el){el.addEventListener('click',function(){var action=el.dataset.action;if(action==='accept'&&!root.confirm(say('تأكيد الموافقة على إجمالي الشحن ','Accept shipping total ')+money(q.total)+say(' والشروط المعروضة وطلب الحجز؟',' and the displayed terms, and request booking?')))return;if(action==='cancel'&&!root.confirm(say('تأكيد إلغاء الطلب؟','Cancel this order?')))return;act(s,action,{quote_id:q&&q.id});});});
    var add=$('shipping-add-package'); if(add) add.addEventListener('click',function(){var host=$('shipping-packages');if(host.children.length<50)host.insertAdjacentHTML('beforeend',packageFields({},host.children.length));});
    var packages=$('shipping-packages');if(packages)packages.addEventListener('click',function(e){var btn=e.target.closest('[data-remove-package]');if(btn&&packages.children.length>1)btn.closest('fieldset').remove();});
  }
  async function act(s,action,data) {
    if(busy)return; busy=true; $('shipping-error').hidden=true;
    $('shipping-detail').querySelectorAll('button,input,select,textarea').forEach(function(el){el.disabled=true;});
    try { data.revision=s.revision; await query(root.sb.rpc('update_manual_shipping',{p_order_id:s.order_id,p_action:action,p_payload:data}));await loadList(false);await loadDetail(s.order_id); }
    catch(err){showError(err);}
    finally{busy=false;$('shipping-detail').querySelectorAll('button,input,select,textarea').forEach(function(el){el.disabled=false;});}
  }
  document.addEventListener('click',function(e){var link=e.target.closest('[data-shipment]');if(!link||busy)return;e.preventDefault();history.replaceState(null,'','?order='+encodeURIComponent(link.dataset.shipment));$('shipping-error').hidden=true;loadDetail(link.dataset.shipment);});
  $('shipping-refresh').addEventListener('click',function(){if(busy)return; $('shipping-error').hidden=true;loadList(false).then(function(){return selected?loadDetail(selected):notices();}).catch(showError);});
  $('shipping-more').addEventListener('click',function(){loadList(true).catch(showError);});
  root.SF_AUTH_READY.then(async function(){if(!root.SF_USER)return;await loadList(false);await notices();var id=new URLSearchParams(location.search).get('order')||(rows[0]&&rows[0].order_id);if(id)await loadDetail(id);else $('shipping-detail').innerHTML='<p class="shipping-empty">'+text('اختر طلب الشحن لعرض بياناته.','Select a shipment to see its details.')+'</p>';}).catch(showError);
})(window);
