// اختبار واجهة العناوين دون بيانات إنتاج أو شبكة.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const read = name => fs.readFileSync(new URL('../' + name, import.meta.url), 'utf8');
const html = read('web-addresses.html');
const tick = () => new Promise(resolve => setImmediate(resolve));
const all = [];
class Element {
  constructor() { this.children=[];this.events={};this.dataset={};this.style={};this.textContent='';this.value='';this.hidden=false;all.push(this); }
  append(...items) { this.children.push(...items); }
  replaceChildren(...items) { this.children=items; }
  addEventListener(name,fn) { this.events[name]=fn; }
  fire(name) { this.events[name]?.({preventDefault(){}}); }
  focus() {}
  scrollIntoView() {}
  reportValidity() { return true; }
  setAttribute(name,value) { this[name]=value; }
}
const elements=new Map([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new Element()]));
const get=id=>{assert(elements.has(id),'Unknown element '+id);return elements.get(id);};
const form=get('address-form');
form.elements=Object.fromEntries([...html.matchAll(/<(?:input|textarea|select)[^>]*name="([^"]+)"/g)].map(m=>[m[1],new Element()]));
form.elements.address_scope.value='domestic';
get('address-editor').hidden=true;
let rows=[],failure,heldResponse,authListener,gpsCallback,uuid=0,tileError,pin,mapRemovals=0,dragEnabled=true;
const calls=[],filters=[],navigations=[],mapEvents={},lookups=[];
const fakeMap={setView(){return fakeMap;},invalidateSize(){},on(event,fn){mapEvents[event]=fn;return fakeMap;},remove(){mapRemovals++;}};
const window={
  I18N:{t:key=>key==='delivery_saudi_country'?'السعودية':key},
  SF_AUTH_READY:Promise.resolve({id:'buyer'}),SF_PROFILE:{full_name:'<img onerror=alert(1)>'},
  crypto:{randomUUID:()=> 'address-'+ ++uuid},confirm:()=>true,
  navigator:{geolocation:{getCurrentPosition(fn){gpsCallback=fn;}}},
  location:{protocol:'http:',replace:value=>navigations.push(value)},
  L:{
    map:()=>fakeMap,
    marker(point,options){
      assert.equal(options.draggable,true);let position=point;
      pin={events:{},dragging:{enable(){dragEnabled=true;},disable(){dragEnabled=false;}},addTo(){return pin;},on(event,fn){pin.events[event]=fn;return pin;},setLatLng(value){position=value;},getLatLng(){return {wrap:()=>({lat:position[0],lng:position[1]})};},remove(){}};
      return pin;
    },
    tileLayer(url,options){
      assert.equal(url,'https://tile.openstreetmap.org/{z}/{x}/{y}.png');assert(options.attribution.includes('openstreetmap.org/copyright'));
      const layer={on(event,fn){tileError=fn;return layer;},addTo(){return layer;}};return layer;
    }
  },
  sb:{
    auth:{onAuthStateChange:fn=>{authListener=fn;}},
    from(table){assert.equal(table,'delivery_addresses');const query={select(){return query;},eq(...args){filters.push(args);return query;},order(){return query;},then(fn){return Promise.resolve({data:rows}).then(fn);}};return query;},
    async rpc(name,payload){
      calls.push({name,payload:JSON.parse(JSON.stringify(payload))});
      if(heldResponse)return heldResponse;
      if(failure){const error=failure;failure=null;return {error};}
      assert.equal(payload.p_expected_user_id,'buyer');
      if(name==='save_structured_delivery_address'){
        const a=payload.p_address;
        rows=rows.filter(r=>r.id!==a.id).map(r=>({...r,is_default:false}));
        rows.push({...a,label:a.city,address_line:[a.country,a.city,a.district,a.street,a.postal_code,a.short_address].filter(Boolean).join('، '),is_default:true});
      }else if(name==='select_delivery_address')rows=rows.map(r=>({...r,is_default:r.id===payload.p_id}));
      else if(name==='delete_delivery_address')rows=rows.filter(r=>r.id!==payload.p_id);
      else assert.fail(name);
      return {data:rows};
    }
  }
};
const context={window,document:{getElementById:get,createElement:()=>new Element(),querySelectorAll:()=>all.filter(el=>el.dataset.addressAction!=null)}};
vm.runInNewContext(read('delivery-addresses.js'),context);await tick();
assert.deepEqual(filters,[['user_id','buyer']]);
assert.equal(get('dash-name').textContent,'<img onerror=alert(1)>');assert.equal(get('dash-name').children.length,0);
assert(!html.includes('<textarea'));assert(html.includes('name="latitude" type="hidden"'));
assert.match(html, /id="address-save" type="button"[^>]*disabled/);
assert.match(html, /<form id="address-form"[^>]*onsubmit="return false;"/);
get('address-add').fire('click');
assert.equal(get('address-saudi-fields').hidden,false);assert.equal(form.elements.country.readOnly,true);
form.elements.city.value='Riyadh';form.elements.district.value='District';
form.fire('submit');await tick();assert.equal(calls.length,0);assert.equal(get('address-status').textContent,'delivery_choose_location');
get('address-locate').fire('click');gpsCallback({coords:{latitude:24.7,longitude:46.7}});
form.elements.short_address.value='abcd١٢٣٤';form.elements.postal_code.value='١٢٣٤٥';form.elements.additional_number.value='٥٦٧٨';form.elements.building.value='١٢٣٤';form.elements.street.value='Street';
failure={code:'PGRST202',message:'Missing function'};get('address-save').fire('click');await tick();
assert.equal(get('address-editor').hidden,false);assert.equal(form.elements.city.value,'Riyadh');
assert.equal(get('address-save-status').textContent,'delivery_setup_required');
assert.equal(get('address-save-status').dataset.error,'true');
assert.equal(get('address-fields').disabled,false);assert.equal(get('address-save').disabled,false);
get('address-save').fire('click');await tick();
assert.equal(calls[0].payload.p_address.id,calls[1].payload.p_address.id);
assert.equal(calls[1].payload.p_address.short_address,'ABCD1234');assert.equal(calls[1].payload.p_address.postal_code,'12345');
assert.equal(rows.length,1);
assert.equal(get('address-save-status').textContent,'delivery_saved');
assert.equal(get('address-save-status').dataset.error,'false');
assert.equal(get('address-editor').hidden,false);assert.equal(get('address-fields').disabled,true);
assert.equal(get('address-save').disabled,true);assert.equal(get('address-update').hidden,false);assert.equal(dragEnabled,false);
const savedCalls=calls.length,savedLatitude=form.elements.latitude.value;
form.fire('submit');get('address-locate').fire('click');
mapEvents.click({latlng:{lat:1,wrap:()=>({lng:2})}});
await tick();assert.equal(calls.length,savedCalls);assert.equal(form.elements.latitude.value,savedLatitude);
get('address-update').fire('click');assert.equal(get('address-fields').disabled,false);assert.equal(dragEnabled,true);
form.elements.city.value='Unsaved city';get('address-cancel').fire('click');
assert.equal(form.elements.city.value,'Riyadh');assert.equal(get('address-fields').disabled,true);
get('address-update').fire('click');form.elements.city.value='Updated city';
let resolveSave;heldResponse=new Promise(resolve=>{resolveSave=resolve;});
form.fire('submit');assert.equal(get('address-fields').disabled,true);assert.equal(get('address-cancel').disabled,true);
get('address-update').fire('click');get('address-cancel').fire('click');assert.equal(form.elements.city.value,'Updated city');
resolveSave({error:{message:'Network unavailable'}});await tick();heldResponse=null;
assert.equal(get('address-fields').disabled,false);assert.equal(form.elements.city.value,'Updated city');
form.fire('submit');await tick();assert.equal(get('address-fields').disabled,true);assert.equal(form.elements.city.value,'Updated city');
// إعادة تحميل البيانات تفتح العنوان المحفوظ للعرض فقط.
get('address-retry').fire('click');await tick();assert.equal(get('address-fields').disabled,true);assert.equal(get('address-update').hidden,false);
console.log('PASS saved view locks fields and map, explicit update, cancel restore, failed save retry and reload');
console.log('PASS domestic fields, map requirement, Arabic digits, separate payload and retry identity');

const cardButton=(index,key)=>get('address-list').children[index].children.find(el=>el.className==='address-actions').children.find(el=>el.textContent===key);
cardButton(0,'delivery_edit').fire('click');assert.equal(form.elements.street.value,'Street');assert.equal(form.elements.short_address.value,'ABCD1234');
form.elements.postal_code.value='123';const count=calls.length;form.fire('submit');await tick();assert.equal(calls.length,count);
form.elements.postal_code.value='12345';form.elements.address_scope.value='international';form.elements.address_scope.fire('change');
assert.equal(get('address-saudi-fields').hidden,true);assert.equal(get('address-saudi-fields').disabled,true);assert.equal(form.elements.latitude.value,'');
form.elements.country.value='France';form.elements.city.value='Paris';form.elements.district.value='Centre';
mapEvents.click({latlng:{lat:48.8,wrap:()=>({lng:2.3})}});
form.elements.short_address.value='ABCD1234';form.elements.street.value='Old Street';
form.fire('submit');await tick();
const foreign=calls.at(-1).payload.p_address;
assert.equal(foreign.country,'France');assert.equal(foreign.city,'Paris');
for(const key of ['street','building','short_address','postal_code','additional_number'])assert.equal(foreign[key],'');
cardButton(0,'delivery_edit').fire('click');assert.equal(form.elements.address_scope.value,'international');assert.equal(get('address-saudi-fields').hidden,true);
console.log('PASS edit roundtrip, national format validation and international fields excluded from saving');

window.SFDeliveryGeocoding={reverse(lat,lon,current){return new Promise(resolve=>lookups.push({lat,lon,current,resolve}));}};
get('address-add').fire('click');
mapEvents.click({latlng:{lat:24.7,wrap:()=>({lng:46.7})}});
mapEvents.click({latlng:{lat:24.8,wrap:()=>({lng:46.8})}});
assert.equal(lookups[0].current(),false);
lookups[0].resolve({country:'Saudi Arabia',country_code:'SA',city:'Old city'});await tick();assert.equal(form.elements.city.value,'');
lookups[1].resolve({country:'Saudi Arabia',country_code:'SA',city:'Riyadh',district:'District',street:'Street',postcode:'12345',building:'1234'});await tick();
assert.equal(form.elements.city.value,'Riyadh');assert.equal(form.elements.street.value,'Street');assert.equal(form.elements.postal_code.value,'12345');
assert.equal(form.elements.short_address.value,'');assert.equal(form.elements.additional_number.value,'');
form.elements.short_address.value='ABCD1234';
pin.setLatLng([48.8,2.3]);pin.events.dragend();
assert.equal(form.elements.short_address.value,'');
form.elements.city.value='User correction';
lookups[2].resolve({country:'France',country_code:'FR',city:'Paris',district:'Centre',street:'Hidden street',postcode:'75000',building:'1234'});await tick();
assert.equal(form.elements.address_scope.value,'international');assert.equal(form.elements.country.value,'France');assert.equal(form.elements.city.value,'User correction');assert.equal(form.elements.street.value,'');
tileError();assert.equal(get('address-map').hidden,true);
get('address-map-retry').fire('click');assert.equal(mapRemovals,1);assert.equal(get('address-map').hidden,false);assert.equal(form.elements.city.value,'User correction');
get('address-cancel').fire('click');
lookups[3].resolve({city:'Late update'});await tick();assert.notEqual(form.elements.city.value,'Late update');
console.log('PASS map autofill, stale result rejection, scope detection, national field clearing and map retry');

window.SFDeliveryGeocoding=null;
get('address-add').fire('click');get('address-locate').fire('click');get('address-cancel').fire('click');get('address-add').fire('click');
gpsCallback({coords:{latitude:1,longitude:2}});assert.equal(form.elements.latitude.value,'');
form.elements.city.value='Jeddah';mapEvents.click({latlng:{lat:21.5,wrap:()=>({lng:39.2})}});form.fire('submit');await tick();
cardButton(0,'delivery_use_default').fire('click');await tick();assert.equal(calls.at(-1).name,'select_delivery_address');
window.confirm=()=>false;const beforeDelete=calls.length;cardButton(1,'delivery_delete').fire('click');await tick();assert.equal(calls.length,beforeDelete);
window.confirm=()=>true;cardButton(1,'delivery_delete').fire('click');await tick();assert.equal(rows.length,1);
cardButton(0,'delivery_edit').fire('click');let finish;heldResponse=new Promise(resolve=>{finish=resolve;});form.fire('submit');authListener('SIGNED_OUT',null);
assert.equal(get('address-list').children.length,0);finish({data:rows});await tick();assert.equal(get('address-list').children.length,0);assert.equal(get('address-add').disabled,true);
assert.deepEqual(navigations,['web-login.html?next=web-addresses.html']);
const redirects=[];const redirectScript=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
vm.runInNewContext(redirectScript,{location:{protocol:'file:',replace:v=>redirects.push(v)}});
vm.runInNewContext(redirectScript,{location:{protocol:'https:',replace(){assert.fail('Do not redirect production');}}});
assert.deepEqual(redirects,['http://127.0.0.1:4173/web-addresses.html']);
console.log('PASS defaults, confirmed deletion, geolocation cancellation, session privacy and local-only redirect');
