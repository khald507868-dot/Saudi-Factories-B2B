import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const read=file=>readFileSync(new URL('../'+file,import.meta.url),'utf8');
const source=read('web-product.html');
// Validate the whole document before extracting helpers: valid isolated functions
// must not hide duplicated code or JavaScript accidentally emitted as page text.
const inlineScripts=[...source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
for(const [,attrs,body] of inlineScripts){
 if(!/\bsrc\s*=|application\/ld\+json/i.test(attrs)&&body.trim())new vm.Script(body);
}
const pageMarkup=source.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'');
assert(!/buyBreakdown|paintBuySums|function validTiers/.test(pageMarkup),'Product code must stay inside script tags');
assert(/<\/html>\s*$/.test(source),'No generated code after the document');
for(const name of ['showCartBar','buyBreakdown','paintBuyTotal','bindCartButton']){
 assert.equal([...source.matchAll(new RegExp('function '+name+'\\(', 'g'))].length,1,'Single definition of '+name);
}
class Element {
 constructor(){this.nodes={};this.style={};this.attrs={};this.events={};this.classes=new Set();this.hidden=false;this.innerHTML='';this.textContent='';this.offsetWidth=300;this.classList={add:key=>this.classes.add(key),remove:key=>this.classes.delete(key)};}
 querySelector(key){return this.nodes[key]??=new Element();}
 setAttribute(key,value){this.attrs[key]=value;}
 addEventListener(key,handler){this.events[key]=handler;}
 contains(node){return node===this||Object.values(this.nodes).some(el=>el.contains(node));}
}
const timer=new Map(),storage=new Map(),docNodes={};let nextTimer=0,currentQty=1,painted;
const document={documentElement:{getAttribute:()=>storage.get('sf_lang')==='en'?'ltr':'rtl'},activeElement:null,
 addEventListener(){},createElement:()=>new Element(),body:{appendChild(){}},
 querySelector:()=>({offsetParent:true,getBoundingClientRect:()=>({left:260,width:40,bottom:70})}),
 getElementById:id=>docNodes[id]};
const context=vm.createContext({document,innerWidth:640,innerHeight:480,addEventListener(){},
 localStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value)},
 setTimeout:(fn,ms)=>{timer.set(++nextTimer,{fn,ms});return nextTimer;},clearTimeout:id=>timer.delete(id),
 escapeHTML:value=>String(value).replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char])),
 wrap:{querySelector:()=>({textContent:'Live product name'})},readQty:()=>currentQty,basePriceText:'25',
 paintBuySums:(subtotal,fee,vat)=>{painted={subtotal,fee,vat};}
});context.window=context;
for(const file of ['currency.js','i18n.js'])vm.runInContext(read(file),context);
vm.runInContext(source.slice(source.indexOf('      var BUY_SHIPPING ='),source.indexOf('      function paintBuyTotal(')),context);
vm.runInContext(source.slice(source.indexOf('      function paintBuyTotal('),source.indexOf('      /* صفوف البيان.')),context);
vm.runInContext(source.slice(source.indexOf('      var cartBar = null;'),source.indexOf('      function validTiers(')),context);
docNodes['buy-total']=new Element();
assert.deepEqual(JSON.parse(JSON.stringify(context.buyBreakdown(25,1))),{unit:25,quantity:1,subtotal:25,fee:.25,vat:3.79,total:29.04});
assert.equal(context.buyBreakdown(15,50).total,871.13);
for(const [unit,qty] of [[0,1],[25,0],[Infinity,1],[25,1.5]])assert.equal(context.buyBreakdown(unit,qty),null);
for(const language of ['ar','en'])for(const currency of ['SAR','USD','KWD']){
 storage.set('sf_lang',language);context.SFCurrency.setCode(currency);
 currentQty=100;context.paintBuyTotal(7);context.showCartBar(100,7);
 const bar=context.cartBar,details=bar.querySelector('.cart-toast-breakdown'),total=bar.querySelector('.cart-toast-price');
 assert.equal(bar.querySelector('.cart-toast-name').textContent,'Live product name');
 for(const key of ['offer_unit_price','order_subtotal','order_shipping','order_payment_fee','order_vat','shipping_pending'])assert(details.innerHTML.includes(context.I18N.t(key)),key);
 for(const value of [7,painted.subtotal,painted.fee,painted.vat])assert(details.innerHTML.includes(context.buyMoney(value)));
 assert(total.innerHTML.includes(docNodes['buy-total'].querySelector('.buy-total-value').innerHTML),'Receipt total agrees with the purchase panel');
 assert(total.innerHTML.includes(context.I18N.t('shipping_before_total')));
 assert(bar.querySelector('.cart-toast-qty').innerHTML.includes('<b>100</b>'));
 assert.equal(total.hidden,false);assert.equal(details.hidden,false);
 assert.equal(timer.size,1,'Repeated additions replace the dismiss timer');
 assert.equal([...timer.values()][0].ms,10000);
 assert.equal(bar.style.maxHeight,'390px');
}
const bar=context.cartBar;
bar.events.mouseenter();assert.equal(timer.size,0,'No dismissal while reading with the pointer');
bar.events.mouseleave();assert.equal(timer.size,1);
document.activeElement=bar.querySelector('.cart-toast-link');bar.events.focusin();assert.equal(timer.size,0);
document.activeElement=null;context.scheduleCartBarHide();assert.equal(timer.size,1);
context.showCartBar(0,0);assert(bar.querySelector('.cart-toast-breakdown').hidden);assert(bar.querySelector('.cart-toast-price').hidden);
assert.equal(bar.querySelector('.cart-toast-breakdown').innerHTML,'','Invalid prices clear the previous receipt');
assert(source.indexOf('var sentUnit = unitForQty(sentQty);')<source.indexOf('SFCommerce.addToCart(product.id, sentQty)'));
assert(source.includes('showCartBar(sentQty, sentUnit);'));
console.log('PASS added-item receipt totals, unit price, shipping pending, fees/VAT, currency rounding, quantity snapshot and reading timeout');
