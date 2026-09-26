(function (root) {
  'use strict';
  var say=function(ar,en){return root.I18N.getLang()==='ar'?ar:en;};
  function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
  var modes=[
    ['sea','الشحن البحري','Sea Freight','الحاويات والشحنات التجارية الكبيرة','Containers and large commercial shipments'],
    ['air','الشحن الجوي','Air Freight','الشحنات السريعة وعالية القيمة','Urgent and high-value shipments'],
    ['road','الشحن البري','Road Freight','النقل بين الدول المتصلة بريًا','Countries connected by road'],
    ['rail','الشحن بالقطار','Rail Freight','حيث تتوفر شبكات السكك الحديدية','Where rail networks are available'],
    ['express','البريد والشحن السريع','Courier / Express','العينات والطرود الصغيرة','Samples and small parcels'],
    ['multimodal','الشحن متعدد الوسائط','Multimodal / Intermodal','الجمع بين أكثر من وسيلة نقل','A combination of transport modes']
  ];
  var services=[
    ['fcl','حاوية كاملة','Full Container Load','FCL'],['lcl','شحن جزئي داخل حاوية','Less than Container Load','LCL'],
    ['break_bulk','بضائع كبيرة غير محوّاة','Oversized, non-containerized cargo','Break Bulk'],
    ['ro_ro','مركبات ومعدات متحركة','Vehicles and rolling equipment','Ro-Ro'],['bulk','بضائع سائبة','Bulk commodities','Bulk Shipping']
  ];
  var routes=[
    ['door_to_door','من المصنع إلى باب المشتري','Door to Door','door'],
    ['door_to_port','من المصنع إلى ميناء / محطة الوصول','Door to Port','port'],
    ['port_to_port','من ميناء / محطة المغادرة إلى الوصول','Port to Port','port'],
    ['port_to_door','من ميناء / محطة المغادرة إلى باب المشتري','Port to Door','door']
  ];
  var terms=['EXW','FCA','FOB','CFR','CIF','CPT','CIP','DAP','DPU','DDP'];
  var seaTerms=['FOB','CFR','CIF'];
  function select(name,title,placeholder,list,selected,service){
    return '<label>'+esc(title)+'<select name="'+name+'" required><option value="">'+esc(placeholder)+'</option>'+list.map(function(item){
      return '<option value="'+item[0]+'"'+(selected===item[0]?' selected':'')+'>'+esc((service?item[3]+' — ':'')+say(item[1],item[2]))+'</option>';
    }).join('')+'</select></label>';
  }
  function group(title,body,extra){return '<fieldset class="export-group" '+(extra||'')+'><legend>'+esc(title)+'</legend>'+body+'</fieldset>';}
  function input(name,label,value,extra){return '<label>'+esc(label)+'<input name="'+name+'" value="'+esc(value)+'" '+extra+'></label>';}
  function markup(p){
    p=p||{};
    var html=group(say('1. وسيلة النقل','1. Transport mode'),select('export_mode',say('وسيلة النقل','Transport mode'),say('اختر وسيلة النقل','Choose a transport mode'),modes,p.transport_mode));
    var sea=select('export_sea_service',say('الخدمة البحرية','Sea freight service'),say('اختر الخدمة البحرية','Choose a sea freight service'),services,p.sea_service,true);
    sea+=group(say('تفاصيل الحاوية','Container details'),'<div class="export-inputs"><label>'+esc(say('حجم الحاوية','Container size'))+'<select name="export_container_type" required><option value="">'+esc(say('اختر الحجم','Choose size'))+'</option>'+['20ft','40ft','40ft_hc'].map(function(size){return '<option value="'+size+'"'+(size===p.container_type?' selected':'')+'>'+({ '20ft':'20ft','40ft':'40ft','40ft_hc':'40ft HC'})[size]+'</option>';}).join('')+'</select></label>'+input('export_container_count',say('عدد الحاويات','Number of containers'),p.container_count||1,'type="number" min="1" max="1000" step="1" required')+'</div>','data-export-fcl hidden disabled');
    sea+='<p class="export-hint" data-export-lcl hidden>'+esc(say('يعتمد تسعير LCL على الحجم CBM والوزن وفق عرض الناقل. يدخل المصنع أبعاد التغليف ووزنه في المرحلة التالية.','LCL pricing uses volume (CBM) and weight under the carrier quote. The factory provides packing dimensions and weight at the next stage.'))+'</p>';
    html+=group(say('2. نوع الخدمة البحرية','2. Sea freight service'),sea,'data-export-sea hidden disabled');
    html+=group(say('مسار استلام وتسليم الشحنة','Pickup and delivery route'),select('export_route',say('مسار التسليم','Delivery route'),say('اختر مسار التسليم','Choose a delivery route'),routes,p.delivery_route)+group(say('نقطة المغادرة','Origin terminal'),input('export_origin_terminal',say('اسم ميناء / محطة المغادرة','Origin port / terminal name'),p.origin_terminal,'type="text" maxlength="200" required'),'data-export-origin hidden disabled'));
    html+=group('Incoterms® 2020','<div class="export-inputs"><label>'+esc(say('شرط التجارة','Trade term'))+'<select name="export_incoterm" required><option value="">'+esc(say('اختر الشرط','Choose a term'))+'</option>'+terms.map(function(term){return '<option value="'+term+'"'+(term===p.incoterm?' selected':'')+'>'+term+'</option>';}).join('')+'</select></label>'+input('export_named_place',say('المكان أو الميناء المحدد للشرط','Named place or port for the term'),p.named_place,'type="text" maxlength="200" required')+'</div><p class="export-hint">'+esc(say('يحدد الشرط توزيع الالتزامات والتكاليف والمخاطر، ويُراجع مع المصنع. FOB وCFR وCIF للشحن البحري فقط.','The term allocates obligations, costs and risks and is reviewed with the factory. FOB, CFR and CIF apply to sea freight only.'))+'</p>');
    return '<section class="shipping-export wide" data-shipping-export><h3>'+esc(say('خيارات التصدير','Export preferences'))+'</h3><p class="export-hint">'+esc(say('اختر متطلبات الشحنة لتجهيز عرض مناسب. تُراجع إمكانية الخدمة وتكلفتها قبل الموافقة والدفع.','Choose your requirements for a suitable quote. Service availability and cost are reviewed before approval and payment.'))+'</p>'+html+'</section>';
  }
  function value(form,name){var field=form.elements[name];return field?field.value:'';}
  function sync(form){
    if(!form.querySelector('[data-shipping-export]'))return;
    var active=value(form,'destination_scope')==='international',mode=value(form,'export_mode'),service=value(form,'export_sea_service'),route=value(form,'export_route');
    function toggle(selector,on){var el=form.querySelector(selector);el.hidden=!on;el.disabled=!on;}
    toggle('[data-export-sea]',active&&mode==='sea');
    toggle('[data-export-fcl]',active&&mode==='sea'&&service==='fcl');
    toggle('[data-export-origin]',active&&route.indexOf('port_to_')===0);
    form.querySelector('[data-export-lcl]').hidden=!(mode==='sea'&&service==='lcl');
    var incoterm=form.elements.export_incoterm;
    Array.from(incoterm.options).forEach(function(option){option.disabled=mode!=='sea'&&seaTerms.includes(option.value);});
    if(mode!=='sea'&&seaTerms.includes(incoterm.value))incoterm.value='';
    var port=route==='door_to_port'||route==='port_to_port';
    form.elements.delivery_type.value=port?'port':'door';
    form.elements.port.parentElement.hidden=!port;
    form.elements.port.disabled=!active||!port;
    form.elements.port.required=active&&port;
  }
  function read(form){
    var mode=value(form,'export_mode'),service=mode==='sea'?value(form,'export_sea_service'):null,route=value(form,'export_route');
    var p={version:1,transport_mode:mode,sea_service:service,container_type:service==='fcl'?value(form,'export_container_type'):null,
      container_count:service==='fcl'?Number(value(form,'export_container_count')):null,delivery_route:route,
      origin_terminal:route.indexOf('port_to_')===0?value(form,'export_origin_terminal').trim():null,
      incoterm:value(form,'export_incoterm'),incoterms_version:'2020',named_place:value(form,'export_named_place').trim()};
    if(!modes.some(function(m){return m[0]===mode;})||!routes.some(function(r){return r[0]===route;})||!terms.includes(p.incoterm)||
      (mode!=='sea'&&seaTerms.includes(p.incoterm))||!p.named_place||p.named_place.length>200||
      (mode==='sea'&&!services.some(function(s){return s[0]===service;}))||
      (service==='fcl'&&(!['20ft','40ft','40ft_hc'].includes(p.container_type)||!Number.isInteger(p.container_count)||p.container_count<1||p.container_count>1000))||
      (route.indexOf('port_to_')===0&&(!p.origin_terminal||p.origin_terminal.length>200)))throw new Error('shipping_invalid_export_preferences');
    return p;
  }
  function summary(p,quote){
    if(!p||typeof p!=='object')return '';
    function name(list,id){var found=list.find(function(x){return x[0]===id;});return found?say(found[1],found[2]):id;}
    var rows=[[say('وسيلة النقل','Transport'),name(modes,p.transport_mode)],[say('مسار التسليم','Delivery route'),name(routes,p.delivery_route)]];
    if(p.transport_mode==='sea')rows.splice(1,0,[say('الخدمة البحرية','Sea service'),name(services,p.sea_service)]);
    if(p.sea_service==='fcl')rows.push([say('الحاويات','Containers'),String(p.container_count)+' × '+(p.container_type==='40ft_hc'?'40ft HC':p.container_type)]);
    if(p.origin_terminal)rows.push([say('نقطة المغادرة','Origin terminal'),p.origin_terminal]);
    rows.push(['Incoterms® '+(p.incoterms_version||'2020'),p.incoterm+' · '+p.named_place]);
    return '<section class="export-summary"><h3>'+esc(quote?say('خيارات التصدير في هذا العرض','Export preferences in this quote'):say('خيارات التصدير المطلوبة','Requested export preferences'))+'</h3><dl>'+rows.map(function(row){return '<div><dt>'+esc(row[0])+'</dt><dd>'+esc(row[1])+'</dd></div>';}).join('')+'</dl></section>';
  }
  root.SFShippingExport={markup:markup,sync:sync,read:read,summary:summary};
})(window);
