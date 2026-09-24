import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../quantity-offers.js',import.meta.url),'utf8');
const reviewsSource=readFileSync(new URL('../reviews-service.js',import.meta.url),'utf8');
class Element {
 constructor(tag='div'){this.tagName=tag;this.children=[];this.attrs={};this.events={};this.style={};this.textContent='';this.hidden=false;}
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
function setup(responses,query='?promotion='+promo,ratingResponses=[]){
 const ids=new Map(['offers-grid','offers-more','offers-status'].map(id=>[id,new Element()]));
 ids.get('offers-more').hidden=true;
 const calls=[],ratingCalls=[],events={};
 const context=vm.createContext({URLSearchParams,location:{search:query},
  document:{readyState:'complete',getElementById:id=>ids.get(id),createElement:tag=>new Element(tag)},
  addEventListener:(name,fn)=>events[name]=fn,
  I18N:{t:key=>({offers_saving:'Save {percent}%',offers_quantity_from:'For {min}+',offers_quantity_range:'For {min}–{max}',offers_intro:'Closest to {percent}%'}[key]||key),money:v=>v,categories:[{en:'Food & Beverages',ar:'Food Arabic'}],categoryName:cat=>cat.ar},
  sfSafeHttpUrl:value=>typeof value==='string'&&value.startsWith('https://')?value:'',
  sb:{rpc:async(name,args)=>{
   if(name==='get_product_ratings'){ratingCalls.push(args.p_product_ids);return ratingResponses.shift()||{data:[]};}
   calls.push({name,args});return responses.shift();
  }}
 });context.window=context;vm.runInContext(reviewsSource,context);vm.runInContext(source,context);
 return {context,ids,calls,ratingCalls,events};
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
const rated=setup([{data:{...page,items:[row,{...row,id:99}],has_more:true}},{data:{...page,items:[{...row,id:100}]}}],undefined,[
 {data:[{product_id:98,rating_avg:4.5,rating_count:3}]},
 {data:[{product_id:100,rating_avg:5,rating_count:1}]}
]);await flush();
const ratingOf=link=>link.children[1].children.find(el=>el.className==='offer-rating');
const rating=ratingOf(rated.ids.get('offers-grid').children[0]);
assert.equal(rating.children[0].attrs['aria-label'],'4.5 / 5');
assert.equal(rating.children[1].textContent,'4.5 (3)');
assert.equal(rating.children[0].children.length,5);
assert.deepEqual(Array.from(rating.children[0].children,star=>star.children[0].style.width),['100%','100%','100%','100%','50%']);
assert.equal(ratingOf(rated.ids.get('offers-grid').children[1]),undefined,'No invented rating for an unrated product');
await rated.ids.get('offers-more').events.click();
assert.deepEqual(JSON.parse(JSON.stringify(rated.ratingCalls)),[[98,99],[100]],'One ratings request per page, mapped by product ID');
assert.equal(ratingOf(rated.ids.get('offers-grid').children[2]).children[1].textContent,'5.0 (1)');
assert.equal(rating.children[1].textContent,'4.5 (3)','Loading more preserves earlier ratings');
const ratingFailure=setup([{data:page}],undefined,[{error:{message:'offline'}}]);await flush();
assert.equal(ratingFailure.ids.get('offers-grid').children[0].href,'web-product.html?id=98');
assert.equal(ratingOf(ratingFailure.ids.get('offers-grid').children[0]),undefined);
assert.equal(ratingFailure.ids.get('offers-status').textContent,'');
assert.equal(empty.ratingCalls.length,0);
const refreshed=setup([{data:page},{data:page}],undefined,[{data:[{product_id:98,rating_avg:4,rating_count:1}]},{data:[{product_id:98,rating_avg:4.5,rating_count:2}]}]);await flush();
refreshed.events.pageshow({persisted:true});await flush();
assert.equal(ratingOf(refreshed.ids.get('offers-grid').children[0]).children[1].textContent,'4.5 (2)');
const html=readFileSync(new URL('../web-offers.html',import.meta.url),'utf8');
assert.ok(html.indexOf('reviews-service.js')<html.indexOf('src="quantity-offers.js'));
console.log('PASS offer links, safe rendering, paging/retry, batched real ratings, fractional stars, unrated products, rating failure and back refresh');
