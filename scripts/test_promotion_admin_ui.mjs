// Isolated browser checks: actual admin page and editor, mocked application data.
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
const root=fileURLToPath(new URL('..',import.meta.url));
const read=f=>readFileSync(join(root,f),'utf8');
const original=read('web-admin.html'), main=original.match(/<script>([\s\S]*?)<\/script>/)[1];
const dir=mkdtempSync(join(tmpdir(),'sf-promo-admin-'));
const mock=String.raw`
window.SF_PROFILE={full_name:'Admin',account_type:'individual',is_admin:IS_ADMIN};
window.SF_USER={id:'admin'};window.SF_AUTH_READY=Promise.resolve();
window.testErrors=[];window.addEventListener('error',e=>testErrors.push(e.message));
window.sb={rpc:async()=>({data:{factories_count:1,products_count:3,units_sold:0,revenue:0}}),from:()=>{const q={select:()=>q,eq:()=>q,order:()=>q,then:(r,j)=>Promise.resolve({data:[]}).then(r,j)};return q;}};
const svg='<svg xmlns="http://www.w3.org/2000/svg" width="400" height="600"><rect width="400" height="600" fill="#c7dfce"/><text x="80" y="250" font-size="40" fill="#183c24">BANNER</text></svg>';
const src='data:image/svg+xml,'+encodeURIComponent(svg);
window.saved=[];window.removed=[];window.rows=[{id:'one',title:'',image_url:src,target_url:'',is_active:true,sort_order:0}];
window.SFPromotions={listPublic:async()=>rows.filter(r=>r.is_active),targetUrl:v=>v,isAdmin:()=>IS_ADMIN,listAdmin:async()=>{if(!IS_ADMIN)throw Error('denied');return rows.slice();},imagePath:()=>true,validateFile:()=>{},save:async(v,file)=>{if(!IS_ADMIN)throw Error('denied');saved.push(v);const row={...v,id:v.id||'new',image_url:src};if(v.id)rows=rows.map(r=>r.id===v.id?row:r);else rows.push(row);return row;},remove:async row=>{if(!IS_ADMIN)throw Error('denied');removed.push(row.id);rows=rows.filter(r=>r.id!==row.id);}};
`;
const tests=async function(){
 const result={},check=(name,ok)=>{if(!ok)throw Error(name);result[name]=true;};
 const wait=()=>new Promise(r=>setTimeout(r,100));
 const el=id=>document.getElementById(id);
 try {
  await wait();
  const tab=document.querySelector('[data-status="promotions"]');
  check('initially_hidden',el('admin-promotions').hidden);
  tab.click();await wait();
  if(!IS_ADMIN){check('admin_only',el('admin-promotions').hidden&&getComputedStyle(document.querySelector('.tabs')).display==='none');await SFPromotionAdmin.show();check('guarded_editor',el('admin-promotions').hidden&&saved.length===0);}
  else {
   check('tab_opens_editor',!el('admin-promotions').hidden&&el('list').hidden&&el('catimg-wrap').hidden);
   check('no_title_field',!el('promo-title'));
   check('thumbnail',!!document.querySelector('.admin-promo-thumbnail'));
   check('fits_screen',document.documentElement.scrollWidth<=innerWidth+1);
   document.querySelector('[data-status="approved"]').click();check('tab_switch',el('admin-promotions').hidden&&!el('list').hidden);
   tab.click();await wait();
   el('home-promo-new').click();const dt=new DataTransfer();dt.items.add(new File(['test'],'banner.png',{type:'image/png'}));el('promo-file').files=dt.files;
   el('home-promo-form').requestSubmit();await wait();
   check('create_banner',saved.length===1&&saved[0].title===''&&rows.length===2);
   document.querySelector('.home-promo-row button').click();el('promo-link').value='https://example.com/offer';el('promo-active').checked=false;el('home-promo-form').requestSubmit();await wait();
   check('edit_banner',saved.length===2&&saved[1].id==='one'&&saved[1].is_active===false&&saved[1].target_url==='https://example.com/offer');
   window.confirm=()=>false;document.querySelector('.home-promo-row button:last-child').click();await wait();check('cancel_delete',removed.length===0);
   window.confirm=()=>true;document.querySelector('.home-promo-row button:last-child').click();await wait();check('delete_banner',removed.length===1&&rows.length===1);
   check('form_reenabled',!el('promo-save').disabled);
  }
  check('no_browser_errors',testErrors.length===0);
 }catch(e){result.error=e.stack;}
 el('result').textContent=JSON.stringify(result);
};
const homeTests=async function(){
 const result={},check=(name,ok)=>{if(!ok)throw Error(name);result[name]=true;};
 const wait=()=>new Promise(r=>setTimeout(r,120));
 try{await new Promise(r=>setTimeout(r,120));
 check('public_banners',document.querySelectorAll('.home-promo-card-image img').length===1);
 check('no_home_management',!document.querySelector('#home-promo-manage,#home-promo-form,.home-promo-card-edit,.home-promo-empty'));
 document.getElementById('home-stats-toggle').click();await new Promise(r=>setTimeout(r,100));
 check('stats_still_work',document.getElementById('home-stats-dialog').open&&document.getElementById('stat-products').textContent==='3');
 document.querySelector('#home-stats-dialog [data-close-dialog]').click();
 check('stats_close',!document.getElementById('home-stats-dialog').open);
 const frames=new Map();let frameId=0,now=performance.now();
 window.requestAnimationFrame=cb=>{frames.set(++frameId,cb);return frameId;};
 window.cancelAnimationFrame=id=>frames.delete(id);
 const step=()=>{now+=50;const pending=Array.from(frames.values());frames.clear();pending.forEach(cb=>cb(now));};
 const refresh=async()=>{window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}));await wait();};
 const sample=rows[0];rows=Array.from({length:4},(_,i)=>({...sample,id:String(i),target_url:'https://example.com/'+i}));
 await refresh();const stage=document.getElementById('home-promo-stage');stage.scrollIntoView();await wait();
 check('all_banners_no_placeholders',stage.querySelectorAll('.home-promo-card:not(.home-promo-copy)').length===4&&!stage.querySelector('.home-promo-vacant'));
 check('no_pagination',!document.getElementById('home-promo-controls'));
 const start=stage.scrollLeft;for(let i=0;i<20;i++)step();check('continuous_motion',Math.abs(stage.scrollLeft-start)>10);
 stage.dispatchEvent(new MouseEvent('mouseenter'));const hovered=stage.scrollLeft;for(let i=0;i<20;i++)step();check('hover_keeps_moving',Math.abs(stage.scrollLeft-hovered)>10);
 stage.dispatchEvent(new MouseEvent('mouseleave'));
 let wraps=0,previous=Math.abs(stage.scrollLeft);
 for(let i=0;i<1600;i++){step();const pos=Math.abs(stage.scrollLeft);if(pos<previous-50)wraps++;previous=pos;}
 check('seamless_wrap',wraps>0&&Math.abs(stage.scrollLeft)>0);
 check('links_preserved',stage.querySelector('a').href.startsWith('https://example.com/'));
 rows=rows.slice(0,2);await refresh();check('short_gallery_fills',stage.scrollWidth>=stage.clientWidth*2&&!stage.querySelector('.home-promo-vacant'));
 rows=[sample];await refresh();check('single_banner_static',!stage.sfStopScroll&&stage.children.length===1);
 rows=[];await refresh();check('empty_state',stage.children.length===1&&!!stage.querySelector('.home-promo-vacant'));
 rows=Array.from({length:4},(_,i)=>({...sample,id:String(i)}));await refresh();
 check('no_browser_errors',testErrors.length===0);
 }catch(e){result.error=e.stack;}document.getElementById('result').textContent=JSON.stringify(result);
};
for(const [lang,admin,width,home] of [['en',true,1440,false],['ar',true,1024,false],['en',false,1440,false],['en',true,1440,true],['ar',false,1440,true]]) {
 const key=(home?'home-':'')+lang+'-'+admin+'-'+width;
 let html=(home?read('index.html'):original).replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'').replace(/href="([^":]+\.css)"/g,(_,p)=>'href="'+pathToFileURL(join(root,p)).href+'"');
 const init='<script>const IS_ADMIN='+admin+';'+mock+'</script>';
 const scripts=['i18n.js','bestsellers-scroll.js',home?'home-panels.js':'promotion-admin.js'].map(f=>'<script src="'+pathToFileURL(join(root,f)).href+'"></script>').join('');
 html=html.replace('</body>','<pre id="result" hidden></pre>'+init+scripts+'<script>I18N.setLang('+JSON.stringify(lang)+');'+(home?'':main)+';('+(home?homeTests:tests).toString()+')();</script></body>');
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
