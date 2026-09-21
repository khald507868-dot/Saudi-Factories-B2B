// فحص رفع الصور ومعاينتها دون تخزين ملفات أو الاتصال بالإنتاج.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
class Element {
  constructor(tag){this.tag=tag;this.children=[];this.dataset={};this.events={};this.disabled=false;this.isConnected=true;this.textContent='';}
  append(...nodes){this.children.push(...nodes);}
  replaceChildren(...nodes){this.children.forEach(n=>{n.isConnected=false;});this.children=nodes;}
  addEventListener(key,fn){this.events[key]=fn;}
  setAttribute(key,value){this[key]=value;}
  all(){return this.children.flatMap(n=>[n,...n.all()]);}
  querySelectorAll(selector){return this.all().filter(n=>selector==='[data-shipping-photos]'?n.dataset.shippingPhotos!==undefined:selector==='[data-shipping-photos][data-editable="true"]'?n.dataset.shippingPhotos!==undefined&&n.dataset.editable==='true':selector==='button,input,select,textarea'?['button','input','select','textarea'].includes(n.tag):false);}
  querySelector(selector){return this.all().find(n=>selector==='[data-photo-list]'&&n.dataset.photoList!==undefined);}
}
let serial=0,fail=false,waitUpload=null,closes=0;
const order='10000000-0000-4000-8000-000000000001',uploads=[],signed=[];
const doc={createElement(tag){const el=new Element(tag);if(tag==='canvas'){el.getContext=()=>({fillRect(){},drawImage(){}});el.toBlob=fn=>fn({size:1234});}return el;}};
const win={I18N:{getLang:()=> 'en'},SUPABASE_URL:'https://test.supabase.co',crypto:{randomUUID:()=> '20000000-0000-4000-8000-'+String(++serial).padStart(12,'0')},
  createImageBitmap:async()=>({width:3000,height:2000,close(){closes++;}}),sb:{storage:{from(bucket){assert.equal(bucket,'shipment-images');return {
    async upload(path,blob,options){uploads.push({path,blob,options});if(waitUpload)await waitUpload;return fail?{error:Error('Offline')}:{data:{path}};},
    async createSignedUrl(path,ttl){signed.push(path);assert.equal(ttl,600);return {data:{signedUrl:'https://test.supabase.co/storage/v1/object/sign/shipment-images/'+path+'?token=test'}};}
  };}}}};
vm.runInNewContext(fs.readFileSync(new URL('../shipping-images.js',import.meta.url),'utf8'),{window:win,document:doc,URL});
const helper=win.SFShippingImages,host=new Element('section');
function group(){const el=new Element('div');el.dataset={shippingPhotos:'',editable:'true',paths:'[]'};host.append(el);return el;}
const first=group();helper.bind(host,order);
const input=first.all().find(n=>n.tag==='input');
const choose=async(files,field=input)=>{field.files=files;await field.events.change();};
const file={type:'image/png',size:1234};
await choose([{type:'image/svg+xml',size:100}]);assert.equal(uploads.length,0);
await choose([{...file,size:10485761}]);assert.equal(uploads.length,0);
await choose(Array(6).fill(file));assert.equal(uploads.length,0);
let resume;waitUpload=new Promise(resolve=>{resume=resolve;});const job=choose([file]);
await new Promise(resolve=>setImmediate(resolve));assert(helper.isBusy());assert(input.disabled);
resume();await job;waitUpload=null;
assert.equal(helper.isBusy(),false);assert.equal(input.disabled,false);assert.equal(helper.paths(first).length,1);
assert.equal(uploads[0].options.upsert,false);assert.equal(uploads[0].options.contentType,'image/jpeg');assert.equal(closes,1);
assert(uploads[0].path.startsWith(order+'/'));assert(signed.includes(uploads[0].path));
fail=true;await choose([file]);assert.equal(helper.paths(first).length,1);assert.equal(helper.isBusy(),false);fail=false;
const second=group();helper.bind(host,order,true);
await choose([file]);assert.equal(helper.paths(first).length,2);
await choose([file],second.all().find(n=>n.tag==='input'));assert.equal(helper.paths(second).length,1);
const button=first.all().find(n=>n.tag==='button');button.events.click();assert.equal(helper.paths(first).length,1);
const img=first.all().find(n=>n.tag==='img');await new Promise(resolve=>setImmediate(resolve));assert(img.src.startsWith('https://test.supabase.co/'));
const bad=new Element('div');bad.dataset.paths=JSON.stringify(['javascript:alert(1)','https://example.com/image.jpg',uploads[0].path]);assert.equal(helper.paths(bad).length,1);
for(let i=0;i<4;i++){const el=group();el.dataset.paths=JSON.stringify(Array(5).fill(uploads[0].path));}
const count=uploads.length;await choose([file]);assert.equal(uploads.length,count);
console.log('PASS image types and size, count limits, private immutable uploads, compression, busy state, partial failure, multiple groups, removal and signed previews');
