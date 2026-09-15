// Native headless Chrome, isolated profile and mocked data; no network or customer writes.
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
const root=resolve(new URL('..',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'));
const read=f=>readFileSync(join(root,f),'utf8');
const page=read('web-factory.html');
const styles=[...page.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m=>m[0]).join('')+
  [...page.matchAll(/<link[^>]+href="([^"]+\.css)"[^>]*>/g)].map(m=>'<style>'+read(m[1])+'</style>').join('');
const section=page.match(/<section class="card certificates-section"[\s\S]*?<\/section>/)[0];
const dir=mkdtempSync(join(tmpdir(),'sf-certificates-ui-'));
const tests=async function(){
  const result={},check=(k,v)=>{if(!v)throw Error(k);result[k]=true;};
  const wait=()=>new Promise(r=>setTimeout(r,100));
  const el=id=>document.getElementById(id);
  try {
    I18N.setLang(LANG);
    // Drive animation frames deterministically while keeping native layout,
    // intersection, resize, decoding and file inputs.
    const frames=new Map();let frameId=0;
    window.requestAnimationFrame=cb=>{frames.set(++frameId,cb);return frameId;};
    window.cancelAnimationFrame=id=>frames.delete(id);
    const step=now=>{const pending=Array.from(frames.values());frames.clear();pending.forEach(cb=>cb(now));};
    document.querySelectorAll('[data-i18n]').forEach(e=>e.textContent=I18N.t(e.dataset.i18n));
    const source=[{id:'one',image_path:'one'},{id:'two',image_path:'two'}];let rows=source.slice(),fail=false,uploads=0,deletes=0;
    const svg='<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560"><rect width="400" height="560" fill="white"/><rect x="20" y="20" width="360" height="520" fill="none" stroke="#3d6947" stroke-width="4"/><text x="200" y="110" font-size="24" text-anchor="middle" fill="#183c24">CERTIFICATE</text><path d="M70 180h260M70 230h260M70 280h260M70 330h260" stroke="#c7dfce" stroke-width="6"/><circle cx="200" cy="440" r="38" fill="#c7dfce"/><text x="200" y="505" font-size="14" text-anchor="middle">TEST SAMPLE</text></svg>';
    window.SF_USER=OWNER?{id:'owner'}:null;
    window.sb={storage:{from:()=>({getPublicUrl:()=>({data:{publicUrl:'data:image/svg+xml,'+encodeURIComponent(svg)}}),remove:async()=>{deletes++;return {};}})},from:()=>{
      let id,operation='read'; const q={select:()=>q,eq:(key,v)=>{if(key==='id')id=v;return q;},order:()=>q,range:()=>q,
        insert:async r=>{rows.push({...r,id:'new'});return {};},delete:()=>{operation='delete';return q;},
        then:(ok,bad)=>Promise.resolve().then(()=>{if(fail)throw Error('offline');if(operation==='delete'){rows=rows.filter(r=>r.id!==id);return {data:[{id}]};}return {data:rows.slice()};}).then(ok,bad)};return q;
    }};
    window.SFUpload={uploadFile:async()=>{uploads++;return {path:'new'};}};
    await SFCertificates.mount({id:1,owner_id:'owner',status:'approved'});await wait();
    const view=el('certificates-view'),pause=document.querySelector('.certificates-pause');
    check('visible',!el('card-certificates').hidden);
    check('owner_controls',el('certificates-add').hidden===!OWNER && !!view.querySelector('.certificate-delete')===OWNER);
    check('image_only',view.querySelectorAll('img').length>1&&!view.querySelector('video'));
    const rect=view.getBoundingClientRect();
    check('no_page_overflow',document.documentElement.scrollWidth<=innerWidth+1);
    check('between_sections',el('card-about').getBoundingClientRect().bottom<=el('card-certificates').getBoundingClientRect().top && el('card-certificates').getBoundingClientRect().bottom<=el('card-posts').getBoundingClientRect().top);
    check('loop_fills_width',Array.from(view.children).some(c=>c.getBoundingClientRect().right>=rect.right-1 && c.getBoundingClientRect().left<=rect.right));
    check('pause_available',!pause.hidden);
    const start=view.scrollLeft;for(let n=100;n<=1000;n+=50)step(n);
    check('moves_sideways',Math.abs(view.scrollLeft-start)>10);
    const before=pause.getAttribute('aria-pressed');pause.click();check('pause_toggle',pause.getAttribute('aria-pressed')!==before);
    view.querySelector('.certificate-open').click();check('viewer',document.querySelector('.certificate-viewer').open);
    document.querySelector('.certificate-viewer-close').click();check('viewer_closed',!document.querySelector('.certificate-viewer').open);
    if(OWNER){
      const pick=async file=>{const dt=new DataTransfer();dt.items.add(file);el('certificates-input').files=dt.files;el('certificates-input').dispatchEvent(new Event('change'));for(let i=0;i<30;i++){await wait();if(!el('certificates-add').disabled)break;}};
      await pick(new File(['invalid'],'document.pdf',{type:'application/pdf'}));check('reject_pdf',uploads===0);
      await pick(new File(['invalid'],'fake.png',{type:'image/png'}));check('reject_fake_image',uploads===0);
      const canvas=document.createElement('canvas');canvas.width=2;canvas.height=2;
      const blob=await new Promise(r=>canvas.toBlob(r,'image/png'));await pick(new File([blob],'valid.png',{type:'image/png'}));
      check('upload_persists',uploads===1&&rows.length===3);
      window.confirm=()=>false;view.querySelector('.certificate-delete').click();await wait();check('cancel_delete',rows.length===3&&deletes===0);
      window.confirm=()=>true;view.querySelector('.certificate-delete').click();await wait();check('delete_persists',rows.length===2&&deletes===1);
    }
    fail=true;await SFCertificates.mount({id:1,owner_id:'owner',status:'approved'});check('retry_visible',!el('certificates-retry').hidden);
    fail=false;el('certificates-retry').click();await wait();check('retry_recovers',el('certificates-retry').hidden);
    rows=[];await SFCertificates.mount({id:1,owner_id:'owner',status:'approved'});check('empty_state',el('card-certificates').hidden===!OWNER);
    rows=source.slice();await SFCertificates.mount({id:1,owner_id:'owner',status:'approved'});await wait();
    const best=document.createElement('section');best.className='bestsellers-section';
    best.innerHTML='<button class="bestsellers-pause"></button><div style="display:flex;overflow:auto;gap:10px;width:450px;max-width:90vw"></div>';
    document.body.appendChild(best);const list=best.querySelector('div');
    for(let n=0;n<2;n++){const card=document.createElement('div');card.className='product-cell';card.style.cssText='flex:0 0 100px;height:10px';list.appendChild(card);}
    SFBestsellersScroll.mount(list);check('short_bestsellers_static',best.querySelector('button').hidden);
    list.sfStopScroll();for(let n=0;n<5;n++)list.appendChild(list.firstChild.cloneNode(true));
    SFBestsellersScroll.mount(list);check('long_bestsellers_loop',!best.querySelector('button').hidden);
    list.sfStopScroll();check('scroll_cleanup',!list.querySelector('.bestsellers-copy'));best.remove();
  } catch(e){result.error=e.stack;}
  el('result').textContent=JSON.stringify(result);
};
for(const [lang,owner,width] of [['ar',true,1440],['en',false,1440],['ar',true,390]]) {
  const key=lang+'-'+owner+'-'+width;
  const html=`<!doctype html><html lang="${lang}" dir="${lang==='ar'?'rtl':'ltr'}"><head><meta charset="utf-8">${styles}</head><body class="store-page"><main class="content-wrap"><div class="card" id="card-about" style="padding:20px"><h2>${lang==='ar'?'نبذة المصنع':'Overview'}</h2></div>${section}<div class="card" id="card-posts" style="padding:20px"><h2>${lang==='ar'?'المنشورات':'Posts'}</h2></div></main><pre id="result" hidden></pre>${['i18n.js','bestsellers-scroll.js','factory-certificates.js'].map(f=>'<script src="'+pathToFileURL(join(root,f)).href+'"></script>').join('')}<script>const LANG=${JSON.stringify(lang)},OWNER=${owner};(${tests.toString()})();</script></body></html>`;
  const file=join(dir,key+'.html');writeFileSync(file,html);
  const profile=join(dir,'profile-'+key),portFile=join(profile,'DevToolsActivePort');
  const chrome=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless','--no-sandbox','--disable-gpu','--no-first-run','--no-default-browser-check','--allow-file-access-from-files','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{stdio:'ignore',windowsHide:true});
  let ws;
  try {
    let port;
    for(let i=0;i<100&&!port;i++){
      await new Promise(r=>setTimeout(r,50));
      try {port=readFileSync(portFile,'utf8').split('\n')[0];} catch {}
    }
    if(!port)throw Error('Chrome debugging port unavailable');
    const targets=await (await fetch('http://127.0.0.1:'+port+'/json')).json();
    ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
    await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});
    let id=0;const pending=new Map();
    ws.onmessage=e=>{const m=JSON.parse(e.data);if(pending.has(m.id)){const [r,j]=pending.get(m.id);pending.delete(m.id);m.error?j(Error(m.error.message)):r(m.result);}};
    const send=(method,params={})=>new Promise((r,j)=>{pending.set(++id,[r,j]);ws.send(JSON.stringify({id,method,params}));});
    await send('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:false});
    await send('Page.navigate',{url:pathToFileURL(file).href});
    let data;
    for(let n=0;n<100;n++){
      await new Promise(r=>setTimeout(r,100));
      const v=await send('Runtime.evaluate',{expression:"document.getElementById('result')?.textContent",returnByValue:true});
      if(v.result.value){data=JSON.parse(v.result.value);break;}
    }
    console.log(key,data||{error:'No result'});if(!data||data.error)process.exitCode=1;
    const shot=await send('Page.captureScreenshot');writeFileSync(join(dir,key+'.png'),Buffer.from(shot.data,'base64'));
  } finally {if(ws)ws.close();chrome.kill();}
}
console.log('Screenshots:',dir);
