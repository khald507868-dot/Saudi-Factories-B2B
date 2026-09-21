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
async function renderAs(role,state='quoted',expired=false){
  const elements=new Map();
  const element=id=>{if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,addEventListener(){},setAttribute(){},removeAttribute(){},querySelectorAll(){return [];},children:[]});return elements.get(id);};
  const buyer=role==='buyer',seller=role==='seller';
  const shipment={order_id:'order',status:state,revision:2,current_quote_id:state==='quoted'?'q':null,orders:{buyer_id:'buyer',subtotal:100,payment_fee:1,vat_amount:15.15,total:116.15,status:'awaiting_shipping',factories:{name:'Factory',owner_id:'seller'}}};
  const quote={id:'q',carrier:'<script>bad()</script>',carrier_quote_reference:'REF',freight:100,additional_fees:20,taxes:5,total:125,estimated_days_min:3,estimated_days_max:7,expires_at:expired?'2000-01-01':'2099-01-01',inclusions:'Pickup',exclusions:'Import duty excluded'};
  let complete;
  const done=new Promise(resolve=>{complete=resolve;});
  const win={I18N:window.I18N,SF_USER:{id:buyer?'buyer':seller?'seller':'admin'},SF_PROFILE:{is_admin:role==='admin'},SF_AUTH_READY:Promise.resolve(),SFShippingNotifications:{refresh:complete},sb:{from(table){let single=false;const q={select(){return q;},order(){return q;},range(){return q;},eq(){return q;},is(){return q;},limit(){return q;},single(){single=true;return q;},then(resolve){return Promise.resolve({data:table==='order_shipments'?(single?shipment:[shipment]):table==='shipping_quotes'?quote:[]}).then(resolve);}};return q;}}};
  vm.runInNewContext(read('shipping-page.js'),{window:win,document:{getElementById:element,addEventListener(){}},URLSearchParams,location:{search:'?order=order'},Date,Promise,encodeURIComponent,history:{replaceState(){}}});
  await Promise.race([done,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Page failed to render: '+element('shipping-error').textContent)),1000))]);
  return element('shipping-detail').innerHTML;
}
const buyer=await renderAs('buyer');assert(buyer.includes('data-action="destination"'));assert(buyer.includes('data-action="accept"'));assert(!buyer.includes('data-action="quote"'));assert(!buyer.includes('data-action="packing"'));assert(buyer.includes('241.15 SAR'));assert(buyer.includes('&lt;script&gt;'));assert(!buyer.includes('<script>bad'));
const seller=await renderAs('seller');assert(seller.includes('data-action="packing"'));assert(!seller.includes('data-action="accept"'));assert(!seller.includes('data-action="quote"'));
const admin=await renderAs('admin');assert(admin.includes('data-action="quote"'));assert(!admin.includes('data-action="accept"'));assert(!admin.includes('data-action="destination"'));
assert(!(await renderAs('buyer','quoted',true)).includes('data-action="accept"'));
assert((await renderAs('admin','booking_requested')).includes('data-action="book"'));
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
const sourceWithHooks=read('shipping-page.js').replace('})(window);','root.shippingTest = {destinationScope, destinationChoice, syncDestinationScope, loadDomesticDestination};\n})(window);');
vm.runInNewContext(sourceWithHooks,{window:testWindow,document:uiDocument});
const helpers=testWindow.shippingTest;
assert.equal(helpers.destinationScope({country:'المملكة العربية السعودية'}),'domestic');
assert.equal(helpers.destinationScope({country:' KSA '}),'domestic');
assert.equal(helpers.destinationScope({country:'UAE'}),'international');
assert.equal(helpers.destinationScope({}),'');
assert(helpers.destinationChoice('domestic').includes('value="domestic" required checked'));
const details={},note={},submit={},savedButton={};
const form={isConnected:true,elements:{destination_scope:{value:''},country:{value:'UAE',setCustomValidity(message){this.validationMessage=message;}},delivery_type:{value:'door'},port:{}},querySelector(selector){return ({'[data-destination-fields]':details,'[data-domestic-note]':note,'[data-use-saved-address]':savedButton,'button[type="submit"]':submit})[selector];}};
helpers.syncDestinationScope(form);assert(details.hidden);assert(details.disabled);assert(submit.disabled);
form.elements.destination_scope.value='domestic';helpers.syncDestinationScope(form);
assert(details.hidden);assert(details.disabled);assert(!note.hidden);assert(submit.disabled);
await helpers.loadDomesticDestination(form,{order_id:'my-order'});
assert(!submit.disabled);assert(note.textContent.includes('Riyadh <warehouse>'));
form.elements.destination_scope.value='international';helpers.syncDestinationScope(form);
assert(!details.hidden);assert(!details.disabled);assert(note.hidden);assert(!submit.disabled);
form.elements.delivery_type.value='port';helpers.syncDestinationScope(form);assert(form.elements.port.required);
form.elements.country.value='السعودية';helpers.syncDestinationScope(form);assert(form.elements.country.validationMessage);
form.elements.country.value='UAE';helpers.syncDestinationScope(form);assert.equal(form.elements.country.validationMessage,'');
form.elements.destination_scope.value='domestic';helpers.syncDestinationScope(form);assert(!form.elements.port.required);assert(details.disabled);assert(!submit.disabled);
savedAddress=null;form._domesticDestination=null;await helpers.loadDomesticDestination(form,{order_id:'my-order'});
assert(submit.disabled);assert(note.textContent.includes('No saved Saudi address'));
form.elements.destination_scope.value='international';helpers.syncDestinationScope(form);assert(!submit.disabled);
console.log('PASS domestic/international toggles, saved-address loading, missing-address guard, port validation and hidden-field disabling');
form.elements.destination_scope.value='domestic';
savedAddress={scope:'domestic',country:'Saudi Arabia',city:'Jeddah',address:'New saved warehouse',saved_address_id:'saved-id'};
form._domesticDestination={address:'Old shipment address'};
const loading=helpers.loadDomesticDestination(form,{order_id:'my-order',destination:{country:'Saudi Arabia'}},true);
assert(submit.disabled);assert(savedButton.disabled);assert.equal(form._domesticDestination,null);
await loading;assert.equal(addressCalls.at(-1),'get_saved_shipping_destination');
assert.equal(form._domesticDestination.saved_address_id,'saved-id');assert(note.textContent.includes('review, then confirm linking'));
assert(!submit.disabled);assert(submit.textContent.includes('Link address'));assert(!savedButton.hidden);
addressError={message:'shipping_saved_address_missing'};
await helpers.loadDomesticDestination(form,{order_id:'my-order'},true);assert(submit.disabled);assert.equal(form._domesticDestination,null);
assert(!savedButton.disabled);assert(uiElements.get('shipping-error').textContent.includes('No saved Saudi'));
assert(buyer.includes('data-use-saved-address'));assert(!seller.includes('data-use-saved-address'));
assert(!(await renderAs('buyer','booking_requested')).includes('data-use-saved-address'));
console.log('PASS explicit saved-address preview, loading guard, retry after failure and editable buyer-only control');
