import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const page=readFileSync(new URL('../web-product.html',import.meta.url),'utf8');
const start=page.indexOf('      var params    = new URLSearchParams');
const route=page.slice(start,page.indexOf('\n\n',start));
const loadStart=page.indexOf('      if (window.sb) {');
const load=page.slice(loadStart,page.indexOf('      /* الهيكل ينتظر',loadStart));
assert(start>0&&loadStart>0&&load.includes('query.maybeSingle()'));
const product={id:48,factory_id:8,name:'Product details',description:'Description',price:12,tiers:[],factories:{id:8,name:'Supplier'}};
for(const [search,expected] of [
 ['?id=48',48],['?product=48',48],['?product_id=48',48],
 ['?factory=8&p=0',48],['?factory=999&id=48',48],
 ['?product=48&id=999',48],['?id=999',null]
]){
 const filters=[],displayed=[],similar=[];let missing=0;
 const query={select(){return this;},eq(key,value){filters.push([key,value]);return this;},order(){return this;},range(){return this;},
  async maybeSingle(){return {data:filters.every(([key,value])=>String(product[key])===value)?product:null};}};
 const context=vm.createContext({URLSearchParams,location:{search},sb:{from:table=>{assert.equal(table,'products');return query;}},
  applyLiveProduct:row=>displayed.push(row),loadSimilar:(...args)=>similar.push(args),
  clearSkeleton:()=>{throw Error('Unexpected load failure');},showMissingProduct:()=>missing++});
 context.window=context;vm.runInContext(route+'\n'+load,context);
 await new Promise(resolve=>setImmediate(resolve));
 if(expected){assert.equal(displayed[0]?.id,expected,search);assert.equal(missing,0);assert.deepEqual(similar,[[8,48]]);}
 else {assert.equal(displayed.length,0);assert.equal(missing,1);}
 if(search.includes('id=48')&&!search.includes('product='))assert.deepEqual(filters,[['id','48']]);
}
console.log('PASS direct id links load details; product/product_id and factory/index links still work; missing products stay unavailable');
