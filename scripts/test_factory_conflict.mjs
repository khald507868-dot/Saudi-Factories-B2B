// اختبار تعارض الحفظ على PostgreSQL معزول ومسار الحفظ الفعلي للويب.
// node scripts/test_factory_conflict.mjs <pglite-directory> [diagnostic-json]
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import vm from 'node:vm';
const {PGlite}=createRequire(resolve(process.argv[2],'package.json'))('@electric-sql/pglite');
const db=new PGlite();
const owner='40000000-0000-4000-8000-000000000001';
const outsider='40000000-0000-4000-8000-000000000002';
const migration=await readFile(new URL('../supabase/migrations/20260912200000_stop_factory_conflict_retries.sql',import.meta.url),'utf8');
const source=await readFile(new URL('../supabase/migrations/20260907130000_price_tiers.sql',import.meta.url),'utf8');
let definition=[...source.matchAll(/create\s+or\s+replace\s+function\s+public\.save_factory_content\s*\([\s\S]*?\bas\s+(\$[a-zA-Z0-9_]*\$)[\s\S]*?\1\s*;/gi)][0][0];
if(process.argv[3]) definition=JSON.parse(await readFile(resolve(process.argv[3]),'utf8')).find(r=>r.object_type==='function'&&r.object_name.startsWith('save_factory_content(')).definition;
let count=0;
async function check(label,fn){await fn();console.log('PASS '+label);count++;}
async function save(uid,stamp,name='Changed',products=null,posts=null){
  await db.exec('begin; set local role authenticated;');
  try{
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[uid??'']);
    const r=await db.query('select public.save_factory_content(1,$1::jsonb,$2::jsonb,$3::jsonb,$4::timestamptz) as result',[JSON.stringify({name}),products===null?null:JSON.stringify(products),posts===null?null:JSON.stringify(posts),stamp]);
    await db.exec('commit');return r.rows[0].result;
  }catch(e){await db.exec('rollback');throw e;}
}
try{
  await db.exec(`
    create role anon; create role authenticated; create schema auth;
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth,public to authenticated,anon;
    create table factories(id bigint primary key,owner_id uuid,name text,about text,cover text,logo text,website text,industry text,company_size text,updated_at timestamptz);
    create table products(id bigint generated always as identity primary key,factory_id bigint,client_key uuid unique,images text[],image text,name text,price numeric,sort_order integer,description text,material text,sizes text,colors text,moq integer,tiers jsonb);
    create table posts(id bigint generated always as identity primary key,factory_id bigint,client_key uuid unique,body text,image text,video text,created_at timestamptz default now());
    create function touch_factory() returns trigger language plpgsql as $$begin new.updated_at:=clock_timestamp();return new;end;$$;
    create trigger touch_factory before update on factories for each row execute function touch_factory();
    insert into factories(id,owner_id,name,updated_at) values(1,'${owner}','Original','2026-09-12T12:00:00Z');
  `);
  await db.exec(definition);
  await db.exec('revoke execute on function save_factory_content(bigint,jsonb,jsonb,jsonb,timestamptz) from public,anon; grant execute on function save_factory_content(bigint,jsonb,jsonb,jsonb,timestamptz) to authenticated;');
  await check('old stale-version check emits the retryable 40001 code',async()=>{
    await assert.rejects(()=>save(owner,'2026-09-11T12:00:00Z'),e=>e.code==='40001');
  });
  const metadata=async()=>(await db.query("select prosrc,proacl::text,proowner,prosecdef,proconfig,oid from pg_proc where proname='save_factory_content'")).rows[0];
  const before=await metadata();
  await check('migration only changes the error code and preserves identity, privileges and body',async()=>{
    await db.exec(migration);await db.exec(migration);
    assert.deepEqual(await metadata(),{...before,prosrc:before.prosrc.replace("errcode = '40001'","errcode = 'PT409'")});
  });
  await check('stale writes return PT409 and preserve factory, products and posts',async()=>{
    await assert.rejects(()=>save(owner,'2026-09-11T12:00:00Z','Stale',[],[]),e=>e.code==='PT409');
    assert.equal((await db.query('select name from factories')).rows[0].name,'Original');
  });
  await check('ownership and authentication still reject unauthorized writes',async()=>{
    for(const uid of [outsider,null]) await assert.rejects(()=>save(uid,'2026-09-12T12:00:00Z'),e=>e.code==='42501');
  });
  await check('current version saves content, products and posts; previous version then conflicts',async()=>{
    const saved=await save(owner,'2026-09-12T12:00:00Z','Valid',[{name:'Product',price:'10',tiers:[{min:1,price:10}]}],[{body:'Post'}]);
    assert.equal(saved.factory.name,'Valid');assert.equal(saved.products.length,1);assert.equal(saved.posts[0].body,'Post');
    await assert.rejects(()=>save(owner,'2026-09-12T12:00:00Z','Stale',[],[]),e=>e.code==='PT409');
    const savedAgain=await save(owner,saved.factory.updated_at,'Second');
    assert.equal(savedAgain.products.length,1);assert.equal(savedAgain.posts.length,1);
  });
  await check('unexpected definition stops migration without changing function',async()=>{
    const current=(await db.query("select pg_get_functiondef('save_factory_content(bigint,jsonb,jsonb,jsonb,timestamptz)'::regprocedure) as body")).rows[0].body;
    await db.exec(current.replace("errcode = 'PT409'","errcode = 'P0001'"));
    const unexpected=await metadata();
    await assert.rejects(()=>db.exec(migration),/Expected exactly one/);await db.exec('rollback');
    assert.deepEqual(await metadata(),unexpected);
  });
}finally{await db.close();}

// تنفيذ نفس وظائف الحفظ من الصفحة مع RPC وهمية، دون نسخة بديلة لمنطقها.
const html=await readFile(new URL('../web-factory.html',import.meta.url),'utf8');
const saveCode=html.slice(html.indexOf('      var saveTimer = null;'),html.indexOf('      /* لا نعتمد على طلب شبكة أثناء الإغلاق.'));
function editor(){
  const pending=[],timers=new Map();let serial=0;
  const ctx={Promise,console:{warn(){}},canEdit:true,factoryRow:{id:1,updated_at:'v1'},data:{name:'Draft',products:[],posts:[]},allFactories:{},factoryId:1,STORE_KEY:'draft',
    localStorage:{setItem(k,v){ctx.draft=JSON.parse(v);}},storageWarning:{textContent:'',classList:{add(){},remove(){}}},I18N:{t:()=> 'Reload before saving'},
    setTimeout(fn){timers.set(++serial,fn);return serial;},clearTimeout(id){timers.delete(id);},sb:{rpc(name,payload){return new Promise(resolve=>pending.push({resolve,payload}));}}};
  ctx.window=ctx;vm.createContext(ctx);vm.runInContext(saveCode,ctx);return {ctx,pending,timers};
}
await check('web conflict stops queued and future automatic requests while retaining draft',async()=>{
  for(const code of ['PT409','40001']){
    const {ctx,pending,timers}=editor();ctx.save();const request=ctx.pushToDb();ctx.data.name='Newer draft';ctx.save();await ctx.pushToDb();
    pending[0].resolve({error:{code,message:'Conflict'}});await request;
    assert.equal(pending.length,1);assert.equal(timers.size,0);assert.equal(ctx.saveConflict,true);
    ctx.save();await ctx.pushToDb();assert.equal(pending.length,1);assert.equal(ctx.draft['1'].name,'Newer draft');assert.equal(ctx.savePending,true);
  }
});
await check('successful queued web edit uses the returned version',async()=>{
  const {ctx,pending}=editor();ctx.save();const request=ctx.pushToDb();ctx.data.name='Next';ctx.save();await ctx.pushToDb();
  pending[0].resolve({data:{factory:{updated_at:'v2'}}});
  for(let i=0;i<10;i++) await Promise.resolve();
  assert.equal(pending.length,2);assert.equal(pending[1].payload.p_expected_updated_at,'v2');
  pending[1].resolve({data:{factory:{updated_at:'v3'}}});await request;assert.equal(ctx.factoryRow.updated_at,'v3');
});
await check('network error permits a later edit without an automatic retry loop',async()=>{
  const {ctx,pending}=editor();ctx.save();const request=ctx.pushToDb();pending[0].resolve({error:{message:'Offline'}});await request;
  assert.equal(pending.length,1);assert.equal(ctx.saveConflict,false);ctx.save();const retry=ctx.pushToDb();assert.equal(pending.length,2);pending[1].resolve({data:{factory:{updated_at:'v2'}}});await retry;
});
console.log(`Completed ${count} checks. No production data accessed.`);
