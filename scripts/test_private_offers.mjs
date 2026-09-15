// Isolated PostgreSQL tests. Never creates a real customer message or order.
// node scripts/test_private_offers.mjs <pglite-package-directory>
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite} = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const read = f => readFileSync(new URL('../'+f,import.meta.url),'utf8');
const uid = n => `10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
let serial = 100;
async function as(user,sql,args=[],role='authenticated') {
  await db.exec('begin; set local role '+role);
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[uid(user),role]);
    const result=await db.query(sql,args); await db.exec('commit'); return result.rows;
  } catch(e) { await db.exec('rollback'); throw e; }
}
const create = (user=1, options={}) => as(user,
  'select * from create_private_chat_offer($1,$2,$3,$4,$5,$6,$7)',
  [options.conversation??1, options.product??1, options.quantity??10, options.price??12, options.days??7, options.notes??'',options.key??uid(++serial)]);
try {
  await db.exec(`create role authenticated;create role anon;create role service_role;create schema auth;create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin bool default false);
    create table factories(id bigint primary key,owner_id uuid references profiles(id),status text);
    create table products(id bigint primary key,factory_id bigint references factories(id),name text,price numeric,images text[],image text);
    create table conversations(id bigint primary key,factory_id bigint references factories(id),individual_id uuid references profiles(id));
    create table messages(id bigint generated always as identity primary key,conversation_id bigint references conversations(id),sender_id uuid references profiles(id),body text,product_id bigint,attachment_url text,attachment_type text);
    create table storage.objects(id int);
    create function in_conversation(cid bigint) returns bool language sql security definer set search_path='' as $$select exists(select 1 from public.conversations c join public.factories f on f.id=c.factory_id where c.id=cid and (c.individual_id=auth.uid() or f.owner_id=auth.uid()))$$;
    grant usage on schema public,auth,storage to authenticated,anon;
  `);
  const schema=read('schema.sql');
  for(const table of ['orders','order_items']) await db.exec(schema.match(new RegExp('create table if not exists public.'+table+' \\([\\s\\S]*?\\n\\);'))[0]);
  await db.exec('alter table orders add shipping numeric(14,2),add payment_fee numeric(14,2),add vat_rate numeric(5,4),add vat_amount numeric(14,2);');
  for(let n=1;n<=5;n++) {
    await db.query('insert into auth.users values($1,$2)',[uid(n),n===5?null:'2026-09-14']);
    await db.query('insert into profiles values($1,$2,false)',[uid(n),[1,3].includes(n)?'factory':'individual']);
  }
  await db.query("insert into factories values(1,$1,'approved'),(2,$2,'approved')",[uid(1),uid(3)]);
  await db.query('insert into conversations values(1,1,$1),(2,1,$2),(3,2,$1)',[uid(2),uid(4)]);
  await db.exec("insert into products values(1,1,'Product <one>',99,array['https://example.com/1.jpg'],''),(2,2,'Other factory',25,'{}','');");
  await db.exec(read('supabase/migrations/20260913210000_account_approval_gate.sql'));
  await db.exec(read('supabase/migrations/20260912150000_secure_message_product_links.sql').match(/create or replace function public.guard_message_insert\(\)[\s\S]*?\$fn\$;/)[0]);
  await db.exec('create trigger messages_insert_guard before insert on messages for each row execute function guard_message_insert();');
  const migration=read('supabase/migrations/20260914120000_private_chat_offers.sql');
  await db.exec(migration); await db.exec(migration);
  const key=uid(++serial),[q]=await create(1,{key});
  assert.equal(q.unit_price,'12.00'); assert.equal(q.total,'174.23');
  assert.equal(q.buyer_id,uid(2)); assert.equal(q.product_image,'https://example.com/1.jpg');
  assert.equal((await create(1,{key}))[0].id,q.id);
  assert.equal((await db.query('select count(*)::int n from messages')).rows[0].n,1);
  await assert.rejects(()=>create(1,{key,price:10}),/offer_invalid/);
  for(const user of [2,3,4,5]) await assert.rejects(()=>create(user),/offer_access_denied/);
  await assert.rejects(()=>create(1,{conversation:3}),/offer_access_denied/);
  await assert.rejects(()=>create(1,{product:2}),/offer_unavailable/);
  for(const options of [{price:0},{price:-1},{price:1.234},{price:'NaN'},{price:1000001},{quantity:0},{quantity:100001},{days:0},{days:31},{notes:'a'.repeat(1001)}]) {
    await assert.rejects(()=>create(1,options),/offer_invalid/);
  }
  for(const user of [1,3,4,5]) await assert.rejects(()=>as(user,'select * from accept_private_chat_offer($1)',[q.id]),/offer_access_denied/);
  for(const user of [1,2]) assert.equal((await as(user,'select * from private_chat_offers')).length,1);
  for(const user of [3,4,5]) assert.equal((await as(user,'select * from private_chat_offers')).length,0);
  await assert.rejects(()=>as(2,'select * from private_chat_offers',[],'anon'),e=>e.code==='42501');
  for(const sql of ["update private_chat_offers set unit_price=1", "delete from private_chat_offers", "insert into private_chat_offers(id) values(gen_random_uuid())"]) await assert.rejects(()=>as(1,sql),e=>e.code==='42501');
  console.log('PASS private RLS, sender/recipient authorization, field validation, no direct writes, and idempotent sending');
  await db.exec('update products set price=300 where id=1');
  const [accepted]=await as(2,'select * from accept_private_chat_offer($1)',[q.id]);
  assert.equal(accepted.status,'accepted'); assert(accepted.order_id);
  assert.equal((await as(2,'select * from accept_private_chat_offer($1)',[q.id]))[0].order_id,accepted.order_id);
  const orders=(await db.query('select * from orders')).rows, items=(await db.query('select * from order_items')).rows;
  assert.equal(orders.length,1); assert.equal(items.length,1);
  assert.equal(orders[0].status,'awaiting_payment'); assert.equal(orders[0].total,'174.23');
  assert.equal(items[0].unit_price,'12.00'); assert.equal(items[0].quantity,'10.000');
  assert.equal((await db.query('select price from products where id=1')).rows[0].price,'300');
  await assert.rejects(()=>as(1,"select * from close_private_chat_offer($1,'withdrawn')",[q.id]),/offer_unavailable/);
  for(const action of ['declined','withdrawn']) {
    const [next]=await create(); const actor=action==='declined'?2:1;
    await assert.rejects(()=>as(actor===1?2:1,'select * from close_private_chat_offer($1,$2)',[next.id,action]),/offer_access_denied/);
    await as(actor,'select * from close_private_chat_offer($1,$2)',[next.id,action]);
    await assert.rejects(()=>as(2,'select * from accept_private_chat_offer($1)',[next.id]),/offer_unavailable/);
  }
  const [expired]=await create(); await db.query("update private_chat_offers set expires_at=now()-interval '1 second' where id=$1",[expired.id]);
  await assert.rejects(()=>as(2,'select * from accept_private_chat_offer($1)',[expired.id]),/offer_unavailable/);
  const [pending]=await create(); await db.exec("update factories set status='rejected' where id=1");
  await assert.rejects(()=>create(),/offer_access_denied/);
  await assert.rejects(()=>as(2,'select * from accept_private_chat_offer($1)',[pending.id]),/offer_unavailable/);
  await db.exec("update factories set status='approved' where id=1");
  await db.query('update auth.users set email_confirmed_at=null where id=$1',[uid(1)]);
  await assert.rejects(()=>create(),/offer_access_denied/);
  await db.query('update auth.users set email_confirmed_at=now() where id=$1',[uid(1)]);
  await db.exec('delete from products where id=1');
  await assert.rejects(()=>as(2,'select * from accept_private_chat_offer($1)',[pending.id]),/offer_unavailable/);
  assert.equal((await db.query('select count(*)::int n from orders')).rows[0].n,1);
  console.log('PASS frozen negotiated price/totals, single-order acceptance, unchanged public price, decline/withdraw/expiry, approval/email gates, and deleted products');
} finally { await db.close(); }
