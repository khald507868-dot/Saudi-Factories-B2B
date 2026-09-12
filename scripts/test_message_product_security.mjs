// اختبارات معزولة لهوية المنتج في المحادثة، بلا اتصال ببيانات المستخدمين.
// node scripts/test_message_product_security.mjs <pglite-directory> [diagnostic-json]
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
if (!process.argv[2]) throw new Error('Pass the isolated PGlite package directory.');
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const buyer = '20000000-0000-4000-8000-000000000001';
const seller = '20000000-0000-4000-8000-000000000002';
const stranger = '20000000-0000-4000-8000-000000000003';
const defs = new Map();
for (const path of ['../schema.sql', '../supabase/migrations/20260909100000_product_card_messages.sql']) {
  const sql = await readFile(new URL(path, import.meta.url), 'utf8');
  for (const match of sql.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\([\s\S]*?\bas\s+(\$[a-zA-Z0-9_]*\$)[\s\S]*?\2\s*;/gi)) defs.set(match[1],match[0]);
}
if (process.argv[3]) {
  const snapshot=JSON.parse(await readFile(resolve(process.argv[3]),'utf8'));
  for(const row of snapshot.filter(x=>x.object_type==='function')) defs.set(row.object_name.split('(')[0].replace(/^public\./,''),row.definition);
}
const fix=await readFile(new URL('../supabase/migrations/20260912150000_secure_message_product_links.sql',import.meta.url),'utf8');
let checks=0;
async function check(name,fn){await fn();checks++;console.log(`PASS ${name}`);}
async function asRole(role,uid,sql,args=[]){
  assert(['anon','authenticated'].includes(role));
  await db.exec('begin');
  try{
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[uid??'']);
    const result=await db.query(sql,args);await db.exec('commit');return result;
  }catch(error){await db.exec('rollback');throw error;}
}
const send=(uid,id,product=null,type='',path='',conversation=1,sender=uid)=>asRole('authenticated',uid,
  'insert into public.messages(id,conversation_id,sender_id,body,product_id,attachment_type,attachment_url) values($1,$2,$3,$4,$5,$6,$7) returning *',
  [id,conversation,sender,'Test message',product,type,path]);
async function denied(fn,code='42501'){await assert.rejects(fn,e=>e.code===code);}
try{
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; grant usage on schema public,auth to anon,authenticated;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create table public.factories(id bigint primary key,owner_id uuid,status text);
    create table public.products(id bigint primary key,factory_id bigint references public.factories,
      name text,image text default '',images text[] default '{}',price numeric,tiers jsonb default '[]',moq integer default 1);
    create table public.conversations(id bigint primary key,individual_id uuid,factory_id bigint references public.factories);
    create table public.messages(id bigint primary key,conversation_id bigint references public.conversations,
      sender_id uuid,body text default '',attachment_url text default '',attachment_type text default '',
      custom_price_id bigint,client_key uuid,created_at timestamptz default now(),updated_at timestamptz default now(),
      is_read boolean default false,product_id bigint references public.products on delete set null,
      constraint messages_attachment_type_check check(attachment_type in ('','image','video','product')),
      constraint messages_product_card_check check(attachment_type<>'product' or product_id is not null));
    insert into public.factories values(1,'${seller}','approved'),(2,'${stranger}','pending');
    insert into public.products(id,factory_id,name,price) values(1,1,'Public product',10),(2,2,'Private product',999),(3,1,'Second public',20);
    insert into public.conversations values(1,'${buyer}',1),(2,'${stranger}',1);
    insert into public.messages(id,conversation_id,sender_id,body,product_id,attachment_type) values
      (1,1,'${seller}','Original offer',1,'product'),(2,1,'${seller}','Legacy card',1,'');
    grant select,insert,update on public.messages to authenticated;
    grant select on public.conversations,public.factories,public.products to authenticated,anon;
    grant delete on public.products to authenticated;
    alter table public.messages enable row level security;
    alter table public.products enable row level security;
    create policy products_select_public on public.products for select to public using(exists(
      select 1 from public.factories f where f.id=products.factory_id and (f.status='approved' or f.owner_id=auth.uid())));
    create policy products_delete_owner on public.products for delete to authenticated using(exists(
      select 1 from public.factories f where f.id=products.factory_id and f.owner_id=auth.uid()));
  `);
  for(const name of ['in_conversation','guard_message_insert','guard_message_columns','get_message_products']){
    assert(defs.has(name),`Missing ${name}`);await db.exec(defs.get(name));
  }
  await db.exec(`
    create policy messages_select_party on public.messages for select to public using(public.in_conversation(conversation_id));
    create policy messages_insert_party on public.messages for insert to public with check(sender_id=auth.uid() and public.in_conversation(conversation_id));
    create policy messages_update_party on public.messages for update to authenticated
      using(public.in_conversation(conversation_id) and sender_id<>auth.uid())
      with check(public.in_conversation(conversation_id) and sender_id<>auth.uid());
    create trigger messages_guard before update on public.messages for each row execute function public.guard_message_columns();
    create trigger messages_guard_insert before insert on public.messages for each row execute function public.guard_message_insert();
    revoke execute on function public.guard_message_insert() from public,anon,authenticated;
    revoke execute on function public.guard_message_columns() from public,anon,authenticated;
    revoke execute on function public.get_message_products(bigint) from public,anon;
    grant execute on function public.get_message_products(bigint) to authenticated;
  `);
  await check('reproduce cross-factory product disclosure through a forged card using synthetic data',async()=>{
    assert.equal((await asRole('authenticated',buyer,'select * from public.products where id=2')).rows.length,0);
    await send(buyer,100,2,'product');
    const {rows}=await asRole('authenticated',buyer,'select * from public.get_message_products(1)');
    assert(rows.some(x=>x.product_id===2 && x.name==='Private product'));
  });
  await check('reproduce replacing a received message product before the fix',async()=>{
    const {rows}=await asRole('authenticated',buyer,'update public.messages set product_id=2 where id=1 returning product_id');
    assert.equal(rows[0].product_id,2);
    await asRole('authenticated',buyer,'update public.messages set product_id=1 where id=1');
  });
  await check('migration is repeatable and preserves existing messages and trigger bindings',async()=>{
    await db.exec(fix);await db.exec(fix);
    assert.equal((await db.query('select count(*)::int n from public.messages')).rows[0].n,3);
    assert.equal((await db.query("select count(*)::int n from pg_trigger where tgrelid='public.messages'::regclass and not tgisinternal")).rows[0].n,2);
  });
  await check('old forged links no longer expose foreign products; valid legacy cards still load',async()=>{
    const {rows}=await asRole('authenticated',buyer,'select * from public.get_message_products(1)');
    assert.deepEqual(rows.map(x=>x.product_id),[1]);
    assert.equal((await asRole('authenticated',buyer,'select * from public.messages where id=100')).rows.length,1);
  });
  await check('both parties may send genuine product cards and product type remains intact',async()=>{
    for(const [uid,id] of [[buyer,101],[seller,102]]){
      const {rows}=await send(uid,id,1,'product');assert.equal(rows[0].attachment_type,'product');
    }
    assert.equal((await send(buyer,103,3,'')).rows[0].attachment_type,'product');
  });
  await check('foreign and nonexistent products, outsiders and forged senders are rejected',async()=>{
    await denied(()=>send(buyer,104,2,'product'));
    await denied(()=>send(seller,104,2,''));
    await denied(()=>send(buyer,104,999,'product'));
    await denied(()=>send(stranger,104,1,'product'));
    await denied(()=>send(buyer,104,1,'product','',2));
    await denied(()=>send(buyer,104,1,'product','',1,seller));
  });
  await check('recipient can mark read but cannot replace/remove product or alter message identity',async()=>{
    const old=(await db.query('select * from public.messages where id=1')).rows[0];
    const {rows}=await asRole('authenticated',buyer,
      "update public.messages set product_id=2,id=999,body='Changed',created_at='2099-01-01',is_read=true where id=1 returning *");
    for(const key of ['product_id','id','body','created_at'])assert.deepEqual(rows[0][key],old[key]);
    assert.equal(rows[0].is_read,true);
    assert.equal((await asRole('authenticated',buyer,'update public.messages set product_id=null where id=1 returning product_id')).rows[0].product_id,1);
  });
  await check('ordinary text and owned photo/video attachments continue to work',async()=>{
    assert.equal((await send(buyer,105)).rows[0].attachment_type,'');
    for(const [type,id] of [['image',106],['video',107]]){
      assert.equal((await send(buyer,id,null,type,`${buyer}/media/file`)).rows[0].attachment_type,type);
    }
    await denied(()=>send(buyer,108,null,'image',`${seller}/media/file`));
    await denied(()=>send(buyer,108,null,'product'),'22023');
    await denied(()=>send(buyer,108,1,'product',`${buyer}/media/file`),'22023');
    await denied(()=>send(buyer,108,null,'other',`${buyer}/media/file`),'22023');
  });
  await check('card details remain private to the conversation and login remains required',async()=>{
    assert.equal((await asRole('authenticated',stranger,'select * from public.get_message_products(1)')).rows.length,0);
    await denied(()=>asRole('anon',null,'select * from public.get_message_products(1)'));
    const {rows}=await db.query("select has_function_privilege('authenticated','public.guard_message_insert()','execute') as allowed");
    assert.equal(rows[0].allowed,false);
  });
  await check('existing parties retain their factory cards if factory approval changes',async()=>{
    await db.exec("update public.factories set status='pending' where id=1");
    assert.equal((await asRole('authenticated',buyer,'select * from public.products where id=1')).rows.length,0);
    assert((await asRole('authenticated',buyer,'select * from public.get_message_products(1)')).rows.some(x=>x.product_id===1));
  });
  await check('deleting a product preserves message text and clears the card via its foreign key',async()=>{
    const before=(await db.query('select count(*)::int n from public.messages')).rows[0].n;
    await asRole('authenticated',seller,'delete from public.products where id=1');
    const {rows}=await asRole('authenticated',buyer,'select * from public.messages where id=1');
    assert.equal(rows[0].product_id,null);assert.equal(rows[0].attachment_type,'');assert.equal(rows[0].body,'Original offer');
    assert.equal((await db.query('select count(*)::int n from public.messages')).rows[0].n,before);
  });
  console.log(`Completed ${checks} message-product security checks. No production data accessed.`);
}finally{await db.close();}
