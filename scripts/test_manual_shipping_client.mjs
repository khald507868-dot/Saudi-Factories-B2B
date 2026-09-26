// اختبارات سلوك العميل والنصوص المعروضة، دون متصفح أو اتصال بالإنتاج.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const window={I18N:{t:k=>k,getLang:()=> 'en',money:v=>String(v)},SF_USER:{id:'buyer'}};
vm.runInNewContext(read('private-offers.js'),{window});
const totals=window.SFPrivateOffers.totals(10,10);
assert.equal(totals.shipping,0);assert.equal(totals.total,116.15);
const base={...totals,id:'quote',buyer_id:'buyer',seller_id:'seller',product_name:'<img src=x onerror=alert(1)>',quantity:10,unit_price:10,status:'pending',expires_at:'2099-01-01'};
const card=window.SFPrivateOffers.cardHTML(base,false);
assert(card.includes('shipping_pending'));assert(card.includes('shipping_before_total'));
assert(card.includes('&lt;img'));assert(!card.includes('<img src=x'));
assert(window.SFPrivateOffers.cardHTML({...base,status:'accepted',order_id:'order'},false).includes('web-shipping.html?order=order'));
assert(window.SFPrivateOffers.cardHTML({...base,status:'accepted',shipping_pricing:'legacy',order_id:'old'},false).includes('href="web-orders.html"'));
console.log('PASS products-only estimates, pending shipping labels, safe offer rendering, and historical order links');

const storage=new Map(),calls=[];let request=0,fail=true;
const commerce={SF_USER:{id:'buyer'},crypto:{randomUUID:()=> 'key-'+(++request)},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},sb:{rpc:async(name,args)=>{calls.push(args);if(fail)throw new Error('Response lost');return {data:{id:'saved-order'}};}}};
vm.runInNewContext(read('commerce-service.js'),{window:commerce});
await assert.rejects(()=>commerce.SFCommerce.createOrder(1),/Response lost/);
// محاكاة إعادة تحميل الصفحة بعد فقدان الرد: مفتاح الطلب يبقى في الجلسة.
vm.runInNewContext(read('commerce-service.js'),{window:commerce});fail=false;
assert.equal((await commerce.SFCommerce.createOrder(1)).id,'saved-order');
assert.equal(calls[0].p_idempotency_key,calls[1].p_idempotency_key);
await commerce.SFCommerce.createOrder(1);assert.notEqual(calls[1].p_idempotency_key,calls[2].p_idempotency_key);
assert.deepEqual(Object.keys(calls[0]).sort(),['p_factory_id','p_idempotency_key']);
console.log('PASS lost-response retries reuse the request key across reload; prices never sent by checkout');

// تشغيل منطق بناء الصفحة على DOM محدود للتحقق من اختيار نماذج الأدوار والنصوص.
// لا يعد هذا فحصاً بصرياً أو اختبار تفاعل كامل للمتصفح.
async function renderAs(role,state='quoted',expired=false,overrides={}){
  const elements=new Map();
  const element=id=>{if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,addEventListener(){},setAttribute(){},removeAttribute(){},querySelectorAll(){return [];},children:[]});return elements.get(id);};
  const buyer=role==='buyer',seller=role==='seller';
  const shipment={order_id:'order',status:state,revision:2,current_quote_id:state==='quoted'?'q':null,buyer_confirmed_at:'2026-09-21',factory_confirmed_at:'2026-09-21',orders:{buyer_id:'buyer',subtotal:100,payment_fee:1,vat_amount:15.15,total:116.15,status:state==='booking_requested'?'paid':'awaiting_shipping',factories:{name:'Factory',owner_id:'seller'}},...overrides};
  const quote={id:'q',carrier:'<script>bad()</script>',carrier_quote_reference:'REF',freight:100,additional_fees:20,taxes:5,total:125,estimated_days_min:3,estimated_days_max:7,expires_at:expired?'2000-01-01':'2099-01-01',inclusions:'Pickup',exclusions:'Import duty excluded'};
  quote.destination_snapshot=shipment.destination;
  let complete;
  const done=new Promise(resolve=>{complete=resolve;});
  const win={I18N:window.I18N,SF_USER:{id:buyer?'buyer':seller?'seller':'admin'},SF_PROFILE:{is_admin:role==='admin'},SF_AUTH_READY:Promise.resolve(),SFShippingNotifications:{refresh:complete},sb:{from(table){let single=false;const q={select(){return q;},order(){return q;},range(){return q;},eq(){return q;},is(){return q;},limit(){return q;},single(){single=true;return q;},then(resolve){return Promise.resolve({data:table==='order_shipments'?(single?shipment:[shipment]):table==='shipping_quotes'?quote:[]}).then(resolve);}};return q;}}};
  vm.runInNewContext(read('shipping-export.js'),{window:win});
  vm.runInNewContext(read('shipping-calling-codes.js'),{window:win});
  vm.runInNewContext(read('shipping-countries.js'),{window:win});
  vm.runInNewContext(read('shipping-page.js'),{window:win,document:{getElementById:element,addEventListener(){}},URLSearchParams,location:{search:'?order=order'},Date,Promise,encodeURIComponent,history:{replaceState(){}}});
  await Promise.race([done,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Page failed to render: '+element('shipping-error').textContent)),1000))]);
  return element('shipping-detail').innerHTML;
}
const buyer=await renderAs('buyer');assert(buyer.includes('data-action="destination"'));assert(buyer.includes('data-action="accept"'));assert(!buyer.includes('data-action="quote"'));assert(!buyer.includes('data-action="packing"'));assert(buyer.includes('241.15 SAR'));assert(buyer.includes('&lt;script&gt;'));assert(!buyer.includes('<script>bad'));
const seller=await renderAs('seller');assert(seller.includes('data-action="packing"'));assert(!seller.includes('data-action="accept"'));assert(!seller.includes('data-action="quote"'));
const admin=await renderAs('admin');assert(admin.includes('data-action="quote"'));assert(!admin.includes('data-action="accept"'));assert(!admin.includes('data-action="destination"'));
const exportPreferences={version:1,transport_mode:'sea',sea_service:'fcl',container_type:'40ft_hc',container_count:2,delivery_route:'port_to_port',origin_terminal:'Jeddah',incoterm:'FOB',incoterms_version:'2020',named_place:'Jeddah <terminal>'};
for(const role of ['buyer','seller','admin']){
  const html=await renderAs(role,'quoted',false,{destination:{scope:'international',country:'UAE',export_preferences:exportPreferences}});
  assert(html.includes('Requested export preferences'));assert(html.includes('Export preferences in this quote'));
  assert(html.includes('Jeddah &lt;terminal&gt;'));assert(!html.includes('Jeddah <terminal>'));
  assert.equal(html.includes('name="export_mode"'),role==='buyer');
  if(role==='buyer'){assert(html.includes('value="sea" selected'));assert(html.includes('value="40ft_hc" selected'));}
}
console.log('PASS buyer export controls, restored selections, party-visible preferences and escaped quote snapshots');
assert(!(await renderAs('buyer','quoted',true)).includes('data-action="accept"'));
assert((await renderAs('admin','booking_requested',false,{pickup_ready_at:'2026-09-22'})).includes('data-action="book"'));
assert(!(await renderAs('admin','booking_requested')).includes('data-action="book"'));
assert(!(await renderAs('buyer','booking_requested')).includes('data-action="book"'));
console.log('PASS role-specific forms, expired quote controls, final estimate, booking controls, and escaped carrier text');

// فحص الانتقال الفعلي بين وضعي النموذج وتعطيل قيود الحقول المخفية.
const noopElement=()=>({addEventListener(){},hidden:true,textContent:''});
const uiElements=new Map();
const uiDocument={addEventListener(){},getElementById(id){if(!uiElements.has(id))uiElements.set(id,noopElement());return uiElements.get(id);}};
let savedAddress={scope:'domestic',country:'Saudi Arabia',address:'Riyadh <warehouse>',contact:'Buyer',phone:'123'},addressError=null;
const addressCalls=[];
const testWindow={I18N:window.I18N,SF_AUTH_READY:{then(){return {catch(){}};}},sb:{rpc:async(name,args)=>{
  addressCalls.push(name);assert(['get_domestic_shipping_destination','get_saved_shipping_destination'].includes(name));assert.equal(args.p_order_id,'my-order');return {data:savedAddress,error:addressError};
}}};
const sourceWithHooks=read('shipping-page.js').replace('})(window);','root.shippingTest = {destinationScope, destinationChoice, syncDestinationScope, loadDomesticDestination, workflow, canReturnStage, requestReturn};\n})(window);');
vm.runInNewContext(read('shipping-calling-codes.js'),{window:testWindow});
vm.runInNewContext(read('shipping-countries.js'),{window:testWindow});
vm.runInNewContext(sourceWithHooks,{window:testWindow,document:uiDocument});
const helpers=testWindow.shippingTest;
assert.equal(helpers.destinationScope({country:'المملكة العربية السعودية'}),'domestic');
assert.equal(helpers.destinationScope({country:' KSA '}),'domestic');
assert.equal(helpers.destinationScope({country:'UAE'}),'international');
assert.equal(helpers.destinationScope({}),'');
const countries=testWindow.SFShippingCountries;
assert.equal(countries.list('en').length,249);
assert.equal(new Set(countries.list('en').map(c=>c.code)).size,249);
for(const value of ['SA','KSA','Saudi Arabia','السعودية','المملكة العربية السعودية'])assert.equal(countries.code(value),'SA');
assert.equal(countries.code('UAE'),'AE');assert.equal(countries.code('الإمارات العربية المتحدة'),'AE');
assert(countries.list('ar').some(c=>c.code==='SA'&&c.name==='المملكة العربية السعودية'));
const countryChoice=helpers.destinationChoice({country:'KSA'});
assert(countryChoice.includes('value="Saudi Arabia" selected'));assert(countryChoice.includes('<select name="country" hidden'));
assert(countryChoice.includes('role="combobox"'));assert(countryChoice.includes('aria-controls="shipping-country-options"'));
assert.equal(countries.search('الامارات','en')[0].code,'AE');assert.equal(countries.search('saudi','ar')[0].code,'SA');
assert.equal(countries.search('UAE','en')[0].code,'AE');assert.equal(countries.search('cote','en')[0].code,'CI');
assert.equal(countries.search('not-a-country','ar').length,0);assert.equal(countries.search('','en').length,249);
assert.equal(countries.phoneSearch('','en').length,245);
assert.equal(countries.phoneSearch('+966','en')[0].value,'SA');assert(countries.phoneSearch('الامارات','en')[0].name.includes('+971'));
assert(countries.phoneSearch('United States','ar').some(c=>c.value==='US'&&c.name.includes('+1')));
const phoneForm={elements:{phone_country_iso:{value:''},phone:{value:'544569187'}}};
assert.throws(()=>countries.readPhone(phoneForm),/shipping_phone_code_required/);
phoneForm.elements.phone_country_iso.value='SA';assert.equal(countries.readPhone(phoneForm).phone_country_code,'+966');assert.equal(countries.readPhone(phoneForm).phone_country_iso,'SA');
for(const number of ['+966 544569187','00966-544569187','+٩٦٦٥٤٤٥٦٩١٨٧']){phoneForm.elements.phone.value=number;assert.equal(countries.readPhone(phoneForm).phone,'544569187');}
phoneForm.elements.phone.value='+971544569187';assert.throws(()=>countries.readPhone(phoneForm),/shipping_invalid_phone_code/);
phoneForm.elements.phone_country_iso.value='';assert.throws(()=>countries.readPhone(phoneForm),/shipping_phone_code_required/);
phoneForm.elements.phone_country_iso.value='+971';assert.equal(countries.readPhone(phoneForm).phone_country_iso,null);assert.equal(countries.readPhone(phoneForm).phone_country_code,'+971');
phoneForm.elements.phone_country_iso.value='invalid';assert.throws(()=>countries.readPhone(phoneForm),/shipping_invalid_phone_code/);
const restoredPhone=await renderAs('buyer','quoted',false,{destination:{country:'UAE',phone:'544569187',phone_country_code:'+966',phone_country_iso:'SA'}});
assert(restoredPhone.includes('value="SA" selected'));assert(!restoredPhone.includes('Code (optional)'));assert(restoredPhone.includes('value="544569187"'));
assert(restoredPhone.match(/id="shipping-phone-code"[^>]*\brequired\b/));
assert(buyer.includes('name="phone_country_iso"'));assert(!seller.includes('name="phone_country_iso"'));
console.log('PASS required calling codes, bilingual/numeric lookup, independent phone country, restoration, prefix deduplication and mismatch guard');
// Exercise actual picker handlers without a live account or browser session.
{
  class Node {
    constructor(){this.children=[];this.dataset={};this.attrs={};this.handlers={};this.hidden=false;this.value='';this.classList={toggle(){}};}
    addEventListener(name,fn){(this.handlers[name]??=[]).push(fn);}
    fire(name,extra={}){const event={preventDefault(){this.prevented=true;},stopPropagation(){},...extra};for(const fn of this.handlers[name]||[])fn(event);return event;}
    setAttribute(k,v){this.attrs[k]=v;} getAttribute(k){return this.attrs[k];} removeAttribute(k){delete this.attrs[k];}
    replaceChildren(){this.children=[];} appendChild(el){this.children.push(el);}
    contains(el){return el===this||this.children.some(child=>child.contains(el));}
    closest(){return this.dataset.countryIndex===undefined?null:this;}
    scrollIntoView(){} setCustomValidity(value){this.validationMessage=value;}
    focus(){this.fire('focus');}
  }
  const input=new Node(),toggle=new Node(),options=new Node(),empty=new Node(),picker=new Node();options.id='test-countries';
  input.ownerDocument={createElement:()=>new Node()};picker.children=[input,toggle,options,empty];
  picker.querySelector=s=>({'[data-country-search]':input,'[data-country-toggle]':toggle,'[role="listbox"]':options,'[data-country-empty]':empty})[s];
  const nativeOptions=countries.list('en').map(c=>({value:c.value,textContent:c.name}));let changes=0;
  const select={value:'Saudi Arabia',options:nativeOptions,get selectedIndex(){return nativeOptions.findIndex(o=>o.value===this.value);},dispatchEvent(event){assert.equal(event.type,'change');assert(event.bubbles);changes++;}};
  const pickerWindow={I18N:window.I18N};
  vm.runInNewContext(read('shipping-calling-codes.js'),{window:pickerWindow});
  vm.runInNewContext(read('shipping-countries.js'),{window:pickerWindow,Event:class {constructor(type,init){this.type=type;Object.assign(this,init);}}});
  const pickerForm={elements:{country:select},querySelector:()=>picker};pickerWindow.SFShippingCountries.bind(pickerForm);
  assert.equal(input.value,'Saudi Arabia');assert(options.hidden);input.focus();assert.equal(input.getAttribute('aria-expanded'),'true');
  input.value='الامارات';input.fire('input');assert.equal(options.children.length,1);assert(input.validationMessage);assert.equal(select.value,'Saudi Arabia');
  assert(input.fire('keydown',{key:'Enter'}).prevented);assert.equal(select.value,'United Arab Emirates');assert.equal(changes,1);assert(options.hidden);assert.equal(input.validationMessage,'');
  input.value='no-result';input.fire('input');assert(!empty.hidden);input.fire('keydown',{key:'Enter'});assert.equal(changes,1);
  input.fire('keydown',{key:'Escape'});assert.equal(input.value,'United Arab Emirates');assert(empty.hidden);assert.equal(input.getAttribute('aria-expanded'),'false');
  input.value='saudi';input.fire('input');options.fire('click',{target:options.children[0]});assert.equal(select.value,'Saudi Arabia');assert.equal(changes,2);
  input.value='uni';input.fire('input');const first=input.getAttribute('aria-activedescendant');input.fire('keydown',{key:'ArrowDown'});assert.notEqual(input.getAttribute('aria-activedescendant'),first);
  input.fire('keydown',{key:'ArrowUp'});assert.equal(input.getAttribute('aria-activedescendant'),first);
  input.fire('keydown',{key:'Tab'});assert(options.hidden);assert.equal(input.value,'Saudi Arabia');
  toggle.fire('click');assert(!options.hidden);toggle.fire('click');assert(options.hidden);
  input.value='Germany';input.fire('input');picker.fire('focusout',{relatedTarget:null});assert.equal(input.value,'Saudi Arabia');assert.equal(changes,2);
  pickerWindow.SFShippingCountries.bind(pickerForm);assert.equal(input.handlers.input.length,1);
  const phoneInput=new Node(),phoneOptions=new Node(),phoneEmpty=new Node(),phoneToggle=new Node(),phonePicker=new Node();
  phoneInput.ownerDocument=input.ownerDocument;phoneOptions.id='test-phone-codes';phonePicker.children=[phoneInput,phoneOptions,phoneEmpty,phoneToggle];
  phonePicker.querySelector=s=>({'[data-country-search]':phoneInput,'[data-country-toggle]':phoneToggle,'[role="listbox"]':phoneOptions,'[data-country-empty]':phoneEmpty})[s];
  const phoneNative=[{value:'',textContent:'Choose code'},...countries.phoneSearch('','en').map(c=>({value:c.value,textContent:c.name}))];let phoneChanges=0;
  const phoneSelect={value:'',options:phoneNative,get selectedIndex(){return phoneNative.findIndex(o=>o.value===this.value);},dispatchEvent(){phoneChanges++;}};
  pickerWindow.SFShippingCountries.bind({elements:{phone_country_iso:phoneSelect},querySelector:()=>phonePicker},true);
  assert.equal(phoneInput.value,'');phoneInput.focus();assert.equal(phoneOptions.children.length,245);assert(!phoneOptions.children.some(c=>c.textContent.includes('optional')));
  phoneInput.value='+966';phoneInput.fire('input');assert.equal(phoneOptions.children.length,1);phoneInput.fire('keydown',{key:'Enter'});
  assert.equal(phoneSelect.value,'SA');assert(phoneInput.value.includes('+966'));assert.equal(select.value,'Saudi Arabia');assert.equal(phoneChanges,1);
  phoneInput.value='';phoneInput.fire('input');assert.equal(phoneSelect.value,'');assert.equal(phoneInput.validationMessage,'');assert.equal(phoneChanges,2);
  phoneInput.value='UAE';phoneInput.fire('input');phoneInput.fire('keydown',{key:'Enter'});assert.equal(phoneSelect.value,'AE');
  phoneToggle.fire('click');phoneOptions.fire('click',{target:phoneOptions.children[0]});assert(phoneSelect.value);
  console.log('PASS searchable country picker: bilingual search, mouse and keyboard selection, no-result guard, cancel, focus exit and change notification');
}
assert(!countryChoice.includes('type="radio"'));assert(!buyer.includes('Outside Saudi Arabia'));assert(!buyer.includes('Inside Saudi Arabia'));
assert.equal((buyer.match(/name="country"/g)||[]).length,1);
assert(helpers.destinationChoice({country:'UAE'}).includes('value="United Arab Emirates" selected'));
assert(helpers.destinationChoice({country:'Historical <country>'}).includes('value="Historical &lt;country&gt;" selected'));
assert.equal(helpers.destinationScope({country:'Saudi Arabia',scope:'international'}),'domestic');
const details={},note={},submit={},savedButton={};
const form={isConnected:true,elements:{destination_scope:{value:''},country:{value:''},delivery_type:{value:'door'},port:{}},querySelector(selector){return ({'[data-destination-fields]':details,'[data-domestic-note]':note,'[data-use-saved-address]':savedButton,'button[type="submit"]':submit})[selector];}};
helpers.syncDestinationScope(form);assert(details.hidden);assert(details.disabled);assert(submit.disabled);
form.elements.country.value='Saudi Arabia';helpers.syncDestinationScope(form);
assert.equal(form.elements.destination_scope.value,'domestic');
assert(details.hidden);assert(details.disabled);assert(!note.hidden);assert(submit.disabled);
await helpers.loadDomesticDestination(form,{order_id:'my-order'});
assert(!submit.disabled);assert(note.textContent.includes('Riyadh <warehouse>'));
form.elements.country.value='United Arab Emirates';helpers.syncDestinationScope(form);
assert.equal(form.elements.destination_scope.value,'international');
assert(!details.hidden);assert(!details.disabled);assert(note.hidden);assert(!submit.disabled);
form.elements.delivery_type.value='port';helpers.syncDestinationScope(form);assert(form.elements.port.required);
form.elements.country.value='السعودية';helpers.syncDestinationScope(form);assert.equal(form.elements.destination_scope.value,'domestic');
form.elements.country.value='UAE';helpers.syncDestinationScope(form);assert.equal(form.elements.destination_scope.value,'international');
form.elements.country.value='Saudi Arabia';helpers.syncDestinationScope(form);assert(!form.elements.port.required);assert(details.disabled);assert(!submit.disabled);
savedAddress=null;form._domesticDestination=null;await helpers.loadDomesticDestination(form,{order_id:'my-order'});
assert(submit.disabled);assert(note.textContent.includes('No saved Saudi address'));
form.elements.country.value='Germany';helpers.syncDestinationScope(form);assert(!submit.disabled);
form.elements.country.value='';helpers.syncDestinationScope(form);assert(submit.disabled);assert(details.disabled);assert.equal(form.elements.destination_scope.value,'');
console.log('PASS localized country selector, legacy selection, country-driven scope, saved-address loading, missing-address guard and hidden-field disabling');
form.elements.country.value='Saudi Arabia';helpers.syncDestinationScope(form);
savedAddress={scope:'domestic',country:'Saudi Arabia',city:'Jeddah',address:'New saved warehouse',saved_address_id:'saved-id'};
form._domesticDestination={address:'Old shipment address'};
const loading=helpers.loadDomesticDestination(form,{order_id:'my-order',destination:{country:'Saudi Arabia'}},true);
assert(submit.disabled);assert(savedButton.disabled);assert.equal(form._domesticDestination,null);
await loading;assert.equal(addressCalls.at(-1),'get_saved_shipping_destination');
assert.equal(form._domesticDestination.saved_address_id,'saved-id');assert(note.textContent.includes('review, then confirm linking'));
assert(!submit.disabled);assert(submit.textContent.includes('Confirm order'));assert(!savedButton.hidden);
addressError={message:'shipping_saved_address_missing'};
await helpers.loadDomesticDestination(form,{order_id:'my-order'},true);assert(submit.disabled);assert.equal(form._domesticDestination,null);
assert(!savedButton.disabled);assert(uiElements.get('shipping-error').textContent.includes('No saved Saudi'));
assert(buyer.includes('data-use-saved-address'));assert(!seller.includes('data-use-saved-address'));
assert(!(await renderAs('buyer','booking_requested')).includes('data-use-saved-address'));
console.log('PASS explicit saved-address preview, loading guard, retry after failure and editable buyer-only control');
assert(!(await renderAs('seller','awaiting_details',false,{buyer_confirmed_at:null,factory_confirmed_at:null})).includes('data-action="packing"'));
assert((await renderAs('seller','awaiting_details',false,{factory_confirmed_at:null})).includes('data-action="packing"'));
assert(!(await renderAs('admin','awaiting_quote',false,{factory_confirmed_at:null})).includes('data-action="quote"'));
const unpaidOrders={buyer_id:'buyer',status:'awaiting_payment',total:241.15,subtotal:100,payment_fee:1,vat_amount:15.15,factories:{owner_id:'seller'}};
assert(!(await renderAs('admin','booking_requested',false,{orders:unpaidOrders})).includes('data-action="book"'));
assert((await renderAs('buyer','booking_requested',false,{orders:unpaidOrders})).includes('outside the platform'));
assert(!(await renderAs('buyer','booking_requested',false,{orders:unpaidOrders})).includes('data-action="payment"'));
assert((await renderAs('seller','booking_requested',false,{orders:unpaidOrders})).includes('data-action="payment"'));
assert((await renderAs('admin','booking_requested',false,{orders:unpaidOrders})).includes('data-action="payment"'));
assert(!(await renderAs('seller','booking_requested')).includes('data-action="payment"'));
const sample={order_id:'sample',status:'awaiting_details',buyer_confirmed_at:null,factory_confirmed_at:null,orders:{status:'awaiting_shipping'}};
const currentStep=markup=>[...markup.matchAll(/<li data-step-state="([^"]+)"/g)].map(m=>m[1]);
assert.deepEqual(currentStep(helpers.workflow(sample,null,[])),['current','waiting','waiting','waiting','waiting','waiting','waiting','waiting']);
sample.buyer_confirmed_at='2026-09-21';assert.deepEqual(currentStep(helpers.workflow(sample,null,[])),['done','current','waiting','waiting','waiting','waiting','waiting','waiting']);
sample.factory_confirmed_at='2026-09-21';assert.deepEqual(currentStep(helpers.workflow(sample,null,[])),['done','done','current','waiting','waiting','waiting','waiting','waiting']);
const readyQuote={expires_at:'2099-01-01',created_at:'2026-09-21'};
assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','current','waiting','waiting','waiting','waiting']);
assert.deepEqual(currentStep(helpers.workflow(sample,{...readyQuote,expires_at:'2000-01-01'},[])),['done','done','current','waiting','waiting','waiting','waiting','waiting']);
sample.orders.status='awaiting_payment';assert(helpers.workflow(sample,{...readyQuote,accepted_at:'2026-09-21'},[]).includes('Awaiting buyer payment'));
sample.orders.status='paid';assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','done','current','waiting','waiting','waiting']);
sample.production_started_at='2026-09-22';assert(helpers.workflow(sample,readyQuote,[]).includes('The order is in production'));
assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','done','current','waiting','waiting','waiting']);
sample.production_completed_at='2026-09-22';assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','done','done','current','waiting','waiting']);
sample.pickup_ready_at='2026-09-22';sample.status='booking_requested';assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','done','done','done','current','waiting']);
assert(helpers.workflow(sample,readyQuote,[]).includes('team has been notified'));
sample.pickup_ready_at=null;sample.production_started_at=null;sample.production_completed_at=null;sample.status='booked';assert.deepEqual(currentStep(helpers.workflow(sample,readyQuote,[])),['done','done','done','done','done','done','current','waiting']);
for(const status of ['collected','departed','arrived']){
  sample.status=status;
  const markup=helpers.workflow(sample,readyQuote,[{kind:'collected',created_at:'2026-09-22T10:00:00Z'}]);
  assert.deepEqual(currentStep(markup),[...Array(7).fill('done'),'current']);
  assert(markup.includes('Shipping company — shipment collected'));
  assert(markup.includes('The shipping company has collected'));
  const lastCard=markup.split('<li data-step-state="done"').at(-1).split('</li>')[0];
  assert(lastCard.includes('<time>'));
  assert(!helpers.workflow(sample,readyQuote,[]).split('<li data-step-state="done"').at(-1).split('</li>')[0].includes('<time>'));
}
sample.status='delivered';sample.orders.status='completed';
const deliveredMarkup=helpers.workflow(sample,readyQuote,[{kind:'delivered',created_at:'2026-09-23T10:00:00Z'}]);
assert.deepEqual(currentStep(deliveredMarkup),Array(8).fill('done'));
assert(deliveredMarkup.includes('All stages are complete.'));
assert(deliveredMarkup.split('<li data-step-state="done"').at(-1).split('</li>')[0].includes('<time>'));
assert(!helpers.workflow(sample,readyQuote,[]).split('<li data-step-state="done"').at(-1).split('</li>')[0].includes('<time>'));
sample.orders.status='cancelled';assert.deepEqual(currentStep(helpers.workflow(sample,null,[])),['stopped','stopped','stopped','stopped','stopped','stopped','stopped','stopped']);
assert(helpers.workflow(sample,null,[{kind:'payment',created_at:'2026-09-21',note:'<img src=x>'}]).includes('&lt;img'));
const shippingHtml=read('web-shipping.html');assert(shippingHtml.indexOf('id="shipping-workflow"')<shippingHtml.indexOf('class="shipping-layout"'));
console.log('PASS approval stages, expiry/cancellation/payment states, sequential role forms and safe history above shipment details');
assert((await renderAs('seller','booking_requested',false,{production_completed_at:'2026-09-22'})).includes('data-action="pickup_ready"'));
assert(!(await renderAs('seller','booking_requested')).includes('data-action="pickup_ready"'));
assert((await renderAs('seller','booking_requested')).includes('data-action="production_start"'));
assert((await renderAs('seller','booking_requested',false,{production_started_at:'2026-09-22'})).includes('data-action="production_complete"'));
for(const role of ['buyer','admin'])assert(!(await renderAs(role,'booking_requested')).includes('data-action="production_start"'));
assert(!(await renderAs('seller','booking_requested',false,{orders:unpaidOrders})).includes('data-action="production_start"'));
assert(!(await renderAs('buyer','booking_requested')).includes('data-action="pickup_ready"'));
assert(!(await renderAs('admin','booking_requested')).includes('data-action="pickup_ready"'));
assert(!(await renderAs('seller','booking_requested',false,{orders:unpaidOrders})).includes('data-action="pickup_ready"'));
assert(!(await renderAs('seller','booking_requested',false,{pickup_ready_at:'2026-09-22'})).includes('data-action="pickup_ready"'));
console.log('PASS production between payment and readiness, factory-only actions, legacy display and booking gate');

assert((await renderAs('admin','booked')).includes('Confirm: shipment collected'));
for(const role of ['buyer','seller'])assert(!(await renderAs(role,'booked')).includes('data-action="track"'));
assert(!(await renderAs('admin','booking_requested')).includes('data-action="track"'));
assert(!(await renderAs('admin','collected')).includes('Confirm: shipment collected'));
console.log('PASS seventh collection stage, actual event timestamp, legacy states and admin-only collection confirmation');

assert((await renderAs('admin','arrived')).includes('Confirm: shipment delivered to customer'));
for(const role of ['buyer','seller'])assert(!(await renderAs(role,'arrived')).includes('data-action="track"'));
for(const status of ['booked','collected','departed','delivered'])assert(!(await renderAs('admin',status)).includes('Confirm: shipment delivered to customer'));
console.log('PASS final delivery stage stays active during transit and completes only on delivery, with recorded timestamp and admin-only confirmation');

// Return controls follow role permissions and retain the confirmed-payment boundary.
const returnSample={order_id:'return-order',status:'awaiting_details',buyer_confirmed_at:'2026-09-21',factory_confirmed_at:null,
 orders:{status:'awaiting_shipping',buyer_id:'buyer',factories:{owner_id:'seller'}}};
testWindow.SF_USER={id:'buyer'};testWindow.SF_PROFILE={is_admin:false};
assert(helpers.workflow(returnSample,null,[]).includes('data-return-stage="2"'));
assert(!helpers.workflow({...returnSample,buyer_confirmed_at:null},null,[]).includes('data-return-stage'));
testWindow.SF_USER.id='stranger';assert(!helpers.workflow(returnSample,null,[]).includes('data-return-stage'));
testWindow.SF_USER.id='buyer';
returnSample.orders.status='paid';returnSample.status='booking_requested';returnSample.factory_confirmed_at='2026-09-21';
assert(!helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage'));
returnSample.production_completed_at='2026-09-22';
assert(!helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage'));
testWindow.SF_USER.id='seller';assert(helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage="6"'));
returnSample.pickup_ready_at='2026-09-22';assert(helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage="7"'));
returnSample.status='booked';assert(!helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage'));
testWindow.SF_USER.id='admin';testWindow.SF_PROFILE.is_admin=true;
assert(helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage="7"'));
returnSample.status='collected';assert(helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage="8"'));
returnSample.status='delivered';assert(helpers.workflow(returnSample,readyQuote,[]).includes('data-return-stage="9"'));
assert(helpers.workflow(returnSample,readyQuote,[{kind:'returned_to_stage_7',note:'<script>reason</script>'}]).includes('&lt;script&gt;reason'));
returnSample.orders.status='cancelled';assert(!helpers.workflow(returnSample,null,[]).includes('data-return-stage'));
console.log('PASS previous-stage controls, buyer/factory/admin permissions, paid boundary, cancelled orders and safe return history');

// Exercise the return dialog lifecycle without invoking browser prompt/confirm.
const modalNodes=new Map();let modal,returnResolve,returnCalls=[],allowedReturn=true,modalLanguage='en';
class ModalNode {
 constructor(){this.events={};this.disabled=false;this.hidden=false;this.value='';this.attrs={};this.isConnected=true;}
 addEventListener(name,fn){this.events[name]=fn;}
 setAttribute(name,value){this.attrs[name]=value;}
 removeAttribute(name){delete this.attrs[name];}
 focus(){modalDocument.activeElement=this;}
}
const opener=new ModalNode();
const modalDocument={activeElement:opener,body:{appendChild(el){modalNodes.set(el.id,el);}},createElement(){
 modal=new ModalNode();modal.form=new ModalNode();modal.submit=new ModalNode();modal.dismiss=[new ModalNode(),new ModalNode()];
 for(const id of ['shipping-return-reason','shipping-return-count','shipping-return-error'])modalNodes.set(id,new ModalNode());
 modal.querySelector=selector=>selector==='form'?modal.form:modal.submit;
 modal.querySelectorAll=selector=>selector==='[data-dismiss]'?modal.dismiss:[...modal.dismiss,modal.submit,modalNodes.get('shipping-return-reason')];
 modal.showModal=()=>{modal.open=true;};modal.close=()=>{modal.open=false;modal.events.close();};modal.remove=()=>modalNodes.delete(modal.id);
 return modal;
}};
modalNodes.set('shipping-error',{textContent:'Request changed. Refresh and review.'});
const modalSay=(ar,en)=>modalLanguage==='ar'?ar:en;
const modalContext=vm.createContext({document:modalDocument,$:id=>modalNodes.get(id),busy:false,uploading:()=>false,
 canReturnStage:()=>allowedReturn,say:modalSay,text:modalSay,esc:s=>String(s).replace(/</g,'&lt;'),isPaid:o=>o.status==='paid',
 act:async(s,action,data)=>{returnCalls.push({action,data});return new Promise(resolve=>{returnResolve=resolve;});}});
const modalSource=read('shipping-page.js');
vm.runInContext(modalSource.slice(modalSource.indexOf('  function requestReturn('),modalSource.indexOf('  function workflow(')),modalContext);
const modalOrder={orders:{status:'awaiting_shipping'}};
modalContext.requestReturn(modalOrder,2);assert(modal.open);assert(modal.innerHTML.includes('Buyer'));
assert.equal(modalDocument.activeElement,modalNodes.get('shipping-return-reason'));
const originalModal=modal;modalContext.requestReturn(modalOrder,2);assert.equal(modal,originalModal,'One dialog at a time');
const submitEvent={preventDefault(){}};
await modal.form.events.submit(submitEvent);assert.equal(returnCalls.length,0);assert.equal(modalNodes.get('shipping-return-error').hidden,false);
const reasonField=modalNodes.get('shipping-return-reason');reasonField.value='  Correct pickup address  ';reasonField.events.input();
assert(modalNodes.get('shipping-return-count').textContent.endsWith(' / 1000'));
const firstSubmit=modal.form.events.submit(submitEvent);assert(modal.submit.disabled);assert(reasonField.disabled);
await modal.form.events.submit(submitEvent);assert.equal(returnCalls.length,1);
let prevented=false;modal.events.cancel({preventDefault(){prevented=true;}});assert(prevented);
modal.dismiss[0].events.click();assert(modal.open,'Do not dismiss an in-flight mutation');
returnResolve(false);await firstSubmit;assert(modal.open);assert(!modal.submit.disabled);assert.equal(reasonField.value,'  Correct pickup address  ');
assert.equal(modalNodes.get('shipping-return-error').textContent,modalNodes.get('shipping-error').textContent);
const retry=modal.form.events.submit(submitEvent);returnResolve(true);await retry;
assert(!modalNodes.has('shipping-return-dialog'));assert.equal(modalDocument.activeElement,opener);
assert.equal(returnCalls[0].data.reason,'Correct pickup address');assert.equal(returnCalls[0].data.stage,2);
modalLanguage='ar';modalContext.requestReturn(modalOrder,2);assert(modal.innerHTML.includes('dir="ltr"'));assert(!modal.innerHTML.includes('Return order'));
modal.dismiss[1].events.click();assert(!modalNodes.has('shipping-return-dialog'));
allowedReturn=false;modalContext.requestReturn(modalOrder,2);assert(!modalNodes.has('shipping-return-dialog'));
console.log('PASS branded return dialog: focus, cancel, reason validation, duplicate-submit guard, error retention, success and Arabic');
