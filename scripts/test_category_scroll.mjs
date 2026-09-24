import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
function setup(direction='ltr',reduced=false,viewport=300,category=true,options={}) {
 let now=100,id=0;const frames=new Map(),timers=new Map(),sizes=[];
 class Element {
  constructor(tag='div',width=0){this.tagName=tag;this.width=width;this.children=[];this.events={};this.style={};this.attrs={};this.hidden=false;this.classes=new Set();this.classList={add:v=>this.classes.add(v),toggle:(v,on)=>on?this.classes.add(v):this.classes.delete(v)};}
  setAttribute(k,v){this.attrs[k]=v;}
  getAttribute(k){return this.attrs[k];}
  addEventListener(k,f){(this.events[k]||=[]).push(f);}
  removeEventListener(k,f){this.events[k]=(this.events[k]||[]).filter(fn=>fn!==f);}
  emit(k,event={}){(this.events[k]||[]).slice().forEach(f=>f(event));}
  contains(el){return el===this||this.children.some(c=>c.contains(el));}
  matches(selector){return selector.split(',').includes(this.tagName);}
  querySelectorAll(selector){return this.children.flatMap(c=>[...(c.matches(selector)?[c]:[]),...c.querySelectorAll(selector)]);}
  querySelector(){return null;}
  appendChild(c){if(c.tagName==='fragment'){[...c.children].forEach(child=>this.appendChild(child));return c;}if(c.parent)c.remove();c.parent=this;this.children.push(c);return c;}
  insertBefore(c,before){if(c.tagName==='fragment'){[...c.children].forEach(child=>this.insertBefore(child,before));return;}c.parent=this;this.children.splice(this.children.indexOf(before),0,c);}
  cloneNode(){const c=new Element(this.tagName,this.width);c.href=this.href;return c;}
  remove(){this.parent.children.splice(this.parent.children.indexOf(this),1);this.parent=null;}
  getBoundingClientRect(){return {width:this.width};}
 }
 const doc=new Element(),root=new Element(),area=new Element(),section=new Element(),view=new Element(),left=new Element('button'),right=new Element('button');
 section.appendChild(area);area.appendChild(view);area.appendChild(left);area.appendChild(right);
 doc.activeElement=null;doc.hidden=false;doc.documentElement=new Element();doc.documentElement.attrs.dir=direction;
 doc.getElementById=id=>id==='dt-catnav-left'?left:id==='dt-catnav-right'?right:null;
 doc.createDocumentFragment=()=>new Element('fragment');
 view.closest=selector=>selector==='.dt-catbar-inner'?area:section;view.clientWidth=viewport;
 for(const [i,w]of [110.25,150.5,180.75,125.25].entries()){const a=new Element('a',w);a.href='web-factories.html?cat='+i;view.appendChild(a);}
 let scroll=0;
 Object.defineProperty(view,'scrollWidth',{get(){const shown=view.children.filter(c=>!c.hidden);return Math.max(view.clientWidth,shown.reduce((n,c)=>n+c.width,0)+Math.max(0,shown.length-1)*22);}});
 Object.defineProperty(view,'scrollLeft',{get:()=>scroll,set(value){const sign=doc.documentElement.attrs.dir==='rtl'?-1:1;scroll=sign*Math.max(0,Math.min(sign*value,view.scrollWidth-view.clientWidth));view.emit('scroll');}});
 view.scrollBy=({left})=>{view.scrollLeft+=left;};
 const media=new Element();media.matches=reduced;
 Object.assign(root,{document:doc,matchMedia:()=>media});
 const context=vm.createContext({window:root,document:doc,console,Set,
  getComputedStyle:()=>({direction:doc.documentElement.attrs.dir,columnGap:'22'}),
  performance:{now:()=>now},requestAnimationFrame:fn=>{frames.set(++id,fn);return id;},cancelAnimationFrame:key=>frames.delete(key),
  setInterval:fn=>{timers.set(++id,fn);return id;},clearInterval:key=>timers.delete(key),
  ResizeObserver:class{constructor(fn){this.fn=fn;sizes.push(this);}observe(){}disconnect(){}},
  MutationObserver:class{observe(){}disconnect(){}},IntersectionObserver:class{observe(){}disconnect(){}}
 });
 for(const file of ['bestsellers-scroll.js','category-scroll.js'])vm.runInContext(readFileSync(new URL('../'+file,import.meta.url),'utf8'),context);
 if(category)root.SFCategoryScroll.mount(view);
 else root.SFBestsellersScroll.mount(view,{itemSelector:'a',sectionSelector:'.dt-catbar',...options});
 const step=(ms=50)=>{now+=ms;const pending=[...frames.values()];frames.clear();pending.forEach(f=>f(now));};
 return {root,doc,view,area,left,right,frames,timers,sizes,step,media};
}
for(const dir of ['ltr','rtl']){
 const s=setup(dir),sign=dir==='rtl'?-1:1,span=654.75;
 assert.equal(s.view.children.length,12);
 assert.equal(s.view.style.scrollBehavior,'auto');
 assert.equal(s.view.children.filter(c=>c.attrs['aria-hidden']==='true'&&c.tabIndex===-1).length,8);
 assert(s.view.children.every((c,i)=>c.href==='web-factories.html?cat='+(i%4)));
 s.step();let before=sign*s.view.scrollLeft,wraps=0;
 for(let i=0;i<600;i++){
  s.step();const after=sign*s.view.scrollLeft;
  if(after<before)wraps++;
  const distance=((after-before)%span+span)%span;
  assert(Math.abs(distance-4)<0.001,dir+': smooth 4px movement across the seam');before=after;
 }
 assert(wraps>=3);
 s.area.emit('mouseenter');before=s.view.scrollLeft;s.step();s.step();assert.equal(s.view.scrollLeft,before);
 s.area.emit('mouseleave');s.step();s.step();assert.notEqual(s.view.scrollLeft,before);
 s.doc.hidden=true;before=s.view.scrollLeft;s.step();assert.equal(s.view.scrollLeft,before);s.doc.hidden=false;s.step();assert.notEqual(s.view.scrollLeft,before);
 const phase=(sign*s.view.scrollLeft)%span;s.sizes[0].fn();assert(Math.abs((sign*s.view.scrollLeft)%span-phase)<0.001);
 s.area.emit('mouseenter');s.view.scrollLeft=sign*(span+100);before=s.view.scrollLeft;
 s.right.emit('click');assert(Math.abs(((s.view.scrollLeft-before)%span+span)%span-240)<0.001,dir+': right arrow moves physically right across a seam');
 s.left.emit('click');assert.equal(s.view.scrollLeft,before);
 s.right.emit('mouseenter');assert.equal(s.timers.size,1);s.root.emit('blur');assert.equal(s.timers.size,0);
 let prevented=false;s.view.emit('wheel',{deltaY:10,deltaX:0,deltaMode:0,preventDefault:()=>prevented=true});assert(prevented);
 s.area.emit('mouseleave');s.step();s.step();
 s.root.SFCategoryScroll.mount(s.view);assert.equal(s.view.children.length,12);assert.equal(s.frames.size,1);
 s.view.sfStopCategoryScroll();assert.equal(s.view.children.length,4);assert.equal(s.frames.size,0);
}
const reduced=setup('ltr',true);const initial=reduced.view.scrollLeft;reduced.step();reduced.step();assert.equal(reduced.view.scrollLeft,initial);
const fits=setup('ltr',false,1000);fits.step();fits.step();assert.equal(fits.view.scrollLeft,0);assert(fits.left.disabled&&fits.right.disabled);
const existing=setup('ltr',false,300,false);existing.step();const previous=existing.view.scrollLeft;existing.step();
assert(Math.abs(existing.view.scrollLeft-previous-1.3)<0.001,'Existing galleries retain their 26px/s speed');
existing.view.emit('mouseenter');const held=existing.view.scrollLeft;existing.step();assert.equal(existing.view.scrollLeft,held);
for(const dir of ['ltr','rtl']){
 const home=setup(dir,false,300,false,{pauseOnHover:false,pauseOnPointerFocus:false});
 home.step();let before=home.view.scrollLeft;
 home.view.emit('mouseenter');home.step();assert.notEqual(home.view.scrollLeft,before,'Homepage keeps moving beneath a stationary pointer');
 home.view.emit('pointerdown');home.doc.activeElement=home.view.children[4];
 before=home.view.scrollLeft;home.step();assert.equal(home.view.scrollLeft,before,'A pointer press pauses while held');
 home.root.emit('pointerup');home.step(2600);
 assert.notEqual(home.view.scrollLeft,before,'Pointer focus after expanding prices does not freeze the strip');
 const span=654.75,sign=dir==='rtl'?-1:1;
 before=sign*home.view.scrollLeft;let wraps=0;
 for(let i=0;i<600;i++){
  home.step();const after=sign*home.view.scrollLeft;
  if(after<before)wraps++;
  assert(Math.abs(((after-before)%span+span)%span-1.3)<0.001,'Continuous motion after a pointer click');
  before=after;
 }
 assert(wraps>0);
 home.doc.emit('keydown',{key:'Tab'});before=home.view.scrollLeft;
 home.step();assert.equal(home.view.scrollLeft,before,'Keyboard focus remains stable for navigation');
 home.doc.activeElement=null;home.view.emit('focusout');home.step();assert.notEqual(home.view.scrollLeft,before);
}
const homeReduced=setup('ltr',true,300,false,{pauseOnHover:false,pauseOnPointerFocus:false});
const stopped=homeReduced.view.scrollLeft;homeReduced.step();homeReduced.step();assert.equal(homeReduced.view.scrollLeft,stopped);
for(const dir of ['ltr','rtl']){
 const similar=setup(dir,false,1800,false,{repeatToFill:true,pauseOnHover:false,pauseOnPointerFocus:false});
 const sign=dir==='rtl'?-1:1,span=654.75;
 similar.step();let before=sign*similar.view.scrollLeft;
 assert(similar.view.children.length>12,'Short similar-product lists fill the viewport and loop seam');
 for(let i=0;i<600;i++){
  similar.step();const after=sign*similar.view.scrollLeft;
  assert(Math.abs(((after-before)%span+span)%span-1.3)<0.001,'Short similar-product loop moves smoothly');
  before=after;
 }
 const phase=(sign*similar.view.scrollLeft)%span;
 similar.sizes[0].fn();
 assert(Math.abs((sign*similar.view.scrollLeft)%span-phase)<0.001,'Expanding tiers keeps the carousel position');
 similar.view.sfStopScroll();assert.equal(similar.view.children.length,4);assert.equal(similar.frames.size,0);
}
console.log('PASS continuous seams, hover options, pointer-focus resume, keyboard focus, reduced motion, arrows and clean remount');
