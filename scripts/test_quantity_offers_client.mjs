import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../quantity-offers.js',import.meta.url),'utf8');
class Element {
 constructor(tag='div'){this.tagName=tag;this.children=[];this.attrs={};this.events={};this.textContent='';this.hidden=false;}
 appendChild(child){this.children.push(child);return child;}
 replaceChildren(){this.children=[];}
 setAttribute(key,value){this.attrs[key]=value;}
 addEventListener(key,fn){this.events[key]=fn;}
 remove(){}
}
const promo='10000000-0000-4000-8000-000000000001';
const row={id:98,name:'<img onerror=alert(1)>',factory_name:'Factory',image:'javascript:alert(1)',images:['https://example.com/product.png'],unit_price:15,reference_price:25,discount_percent:40,min_quantity:50,max_quantity:null,reference_min:1,reference_max:49};
const page={category:'Food & Beverages',percent:40,items:[row],has_more:false};
const flush=()=>new Promise(r=>setImmediate(r));
function setup(responses,query='?promotion='+promo){
 const ids=new Map(['offers-grid','offers-more','offers-status'].map(id=>[id,new Element()]));
 ids.get('offers-more').hidden=true;
 const calls=[],events={};
 const context=vm.createContext({URLSearchParams,location:{search:query},
  document:{readyState:'complete',getElementById:id=>ids.get(id),createElement:tag=>new Element(tag)},
  addEventListener:(name,fn)=>events[name]=fn,
  I18N:{t:key=>({offers_saving:'Save {percent}%',offers_quantity_from:'For {min}+',offers_quantity_range:'For {min}–{max}',offers_intro:'Closest to {percent}%'}[key]||key),money:v=>v,categories:[{en:'Food & Beverages',ar:'Food Arabic'}],categoryName:cat=>cat.ar},
  sfSafeHttpUrl:value=>typeof value==='string'&&value.startsWith('https://')?value:'',
  sb:{rpc:async(name,args)=>{calls.push({name,args});return responses.shift();}}
 });context.window=context;vm.runInContext(source,context);
 return {context,ids,calls,events};
}
const s=setup([{data:page}]);await flush();
assert.equal(s.calls[0].name,'get_promotion_quantity_offers');
assert.equal(s.calls[0].args.p_offset,0);assert.equal(s.calls[0].args.p_promotion_id,promo);
assert.equal(s.ids.get('offers-grid').children.length,1);
const link=s.ids.get('offers-grid').children[0];
assert.equal(link.href,'web-product.html?id=98');
assert.equal(link.children[0].children[0].src,'https://example.com/product.png');
assert.equal(link.children[1].children[0].textContent,row.name);
assert.equal(link.children[1].children[0].attrs['data-sf-translate'],'');
assert.equal(link.children[0].children[1].textContent,'Save 40%');
assert.equal(link.children[1].children[3].textContent,'For 50+');
assert.equal(s.ids.get('offers-more').hidden,true);
const p=setup([{data:{...page,has_more:true}},{error:{message:'offline'}},{data:{...page,items:[{...row,id:99}]}}]);await flush();
await p.ids.get('offers-more').events.click();
assert.equal(p.ids.get('offers-status').textContent,'catalog_search_failed');
assert.equal(p.ids.get('offers-more').disabled,false);
assert.equal(p.ids.get('offers-grid').children.length,1);
await p.ids.get('offers-more').events.click();
assert.deepEqual(p.calls.map(c=>c.args.p_offset),[0,1,1]);
assert.equal(p.ids.get('offers-grid').children.length,2);
const empty=setup([{data:{...page,items:[]}}]);await flush();assert.equal(empty.ids.get('offers-status').textContent,'offers_empty');
const unavailable=setup([{data:null}]);await flush();assert.equal(unavailable.ids.get('offers-status').textContent,'offers_unavailable');
const invalid=setup([],'?promotion=bad');await flush();assert.equal(invalid.calls.length,0);
assert.equal(invalid.ids.get('offers-status').textContent,'offers_unavailable');
const back=setup([{data:page},{data:null}]);await flush();back.events.pageshow({persisted:true});await flush();
assert.equal(back.ids.get('offers-grid').children.length,0);
assert.deepEqual(back.calls.map(c=>c.args.p_offset),[0,0]);
const missing=setup([{error:{code:'PGRST202'}}]);await flush();
assert.equal(missing.ids.get('offers-status').textContent,'catalog_search_failed');assert.equal(missing.ids.get('offers-more').hidden,false);
console.log('PASS offer links, safe rendering, actual saving/quantity, paging, retry, empty/expired/invalid offers and back navigation');
