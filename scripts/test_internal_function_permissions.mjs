// اختبارات PostgreSQL معزولة؛ تقبل تصدير التشخيص JSON اختيارياً لمطابقة الإنتاج.
// node scripts/test_internal_function_permissions.mjs <pglite-directory> [diagnostic-json]
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

if (!process.argv[2]) throw new Error('Pass the isolated PGlite package directory.');
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const member = '20000000-0000-4000-8000-000000000001';
const other = '20000000-0000-4000-8000-000000000002';
const factoryOwner = '20000000-0000-4000-8000-000000000003';
const orderId = '30000000-0000-4000-8000-000000000001';
const directory = new URL('../supabase/migrations/', import.meta.url);
const fix = await readFile(new URL('20260912140000_restrict_internal_functions.sql', directory), 'utf8');
const definitions = new Map();
const files = [new URL('../schema.sql', import.meta.url),
  ...(await readdir(directory)).filter(x => x.endsWith('.sql')).sort().map(x => new URL(x, directory))];
for (const file of files) {
  const sql = await readFile(file, 'utf8');
  for (const match of sql.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\([\s\S]*?\bas\s+(\$[a-zA-Z0-9_]*\$)[\s\S]*?\2\s*;/gi)) {
    definitions.set(match[1], match[0]);
  }
}
let snapshot = null;
if (process.argv[3]) {
  snapshot = JSON.parse(await readFile(resolve(process.argv[3]), 'utf8'));
  for (const row of snapshot.filter(x => x.object_type === 'function')) {
    definitions.set(row.object_name.split('(')[0].replace(/^public\./, ''), row.definition);
  }
}
const triggerNames = ['category_images_stamp', 'guard_custom_price_columns', 'guard_factory_columns',
  'guard_message_columns', 'guard_message_insert', 'guard_post_columns', 'guard_profile_columns',
  'handle_new_user', 'product_reviews_guard', 'touch_conversation_from_message'];
let checks = 0;
async function check(name, fn) { await fn(); checks++; console.log(`PASS ${name}`); }
async function asRole(role, uid, sql, args = []) {
  assert(['anon', 'authenticated'].includes(role));
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    const result = await db.query(sql, args);
    await db.exec('commit'); return result;
  } catch (error) { await db.exec('rollback'); throw error; }
}
async function load(name) { assert(definitions.has(name), `Missing ${name}`); await db.exec(definitions.get(name)); }
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    grant usage on schema auth, public to anon, authenticated;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create table public.profiles(id uuid primary key, is_admin boolean default false,
      account_type text default 'individual', full_name text default '', company_image text default '');
    create table public.factories(id bigint primary key, owner_id uuid, status text);
    create table public.products(id bigint primary key, factory_id bigint, name text,
      image text, images text[], price numeric, tiers jsonb, moq integer);
    create table public.orders(id uuid primary key, buyer_id uuid);
    create table public.order_items(order_id uuid, product_id bigint);
    create table public.product_reviews(id bigint generated always as identity primary key,
      product_id bigint, author_id uuid, rating smallint, body text,
      created_at timestamptz default now(), updated_at timestamptz default now());
    create table public.conversations(id bigint primary key, individual_id uuid, factory_id bigint,
      last_message_at timestamptz default '2000-01-01');
    create table public.messages(id bigint primary key, conversation_id bigint, product_id bigint,
      sender_id uuid, body text, attachment_url text, attachment_type text, custom_price_id bigint,
      client_key uuid, created_at timestamptz default now(), is_read boolean default false);
    create table public.category_images(category_id text primary key, image_url text,
      updated_by uuid, updated_at timestamptz);
    insert into public.profiles(id,full_name) values ('${member}','Buyer'),('${other}','Other'),('${factoryOwner}','Factory');
    insert into public.factories values (1,'${factoryOwner}','approved');
    insert into public.products values (1,1,'Product','https://example.test/image.webp',
      array[]::text[],10,'[]',1);
    insert into public.orders values ('${orderId}','${member}');
    insert into public.order_items values ('${orderId}',1);
    insert into public.product_reviews(product_id,author_id,rating,body) values
      (1,'${member}',5,'Bought this'),(1,'${other}',4,'Public review');
    insert into public.conversations(id,individual_id,factory_id) values (1,'${member}',1);
    insert into public.messages(id,conversation_id,product_id,sender_id,body) values (1,1,1,'${member}','Original');
    alter table public.orders enable row level security;
    alter table public.order_items enable row level security;
    grant select on public.orders, public.order_items to anon, authenticated;
    grant select, update on public.profiles, public.product_reviews, public.messages to authenticated;
    grant insert, select on public.category_images to authenticated;
  `);
  const availableTriggers = triggerNames.filter(name => definitions.has(name));
  if (snapshot) assert.equal(availableTriggers.length, triggerNames.length);
  // بعض المشغلات القديمة موجودة في الإنتاج فقط؛ التصدير يتيح اختبارها أيضاً.
  for (const name of ['is_admin', 'has_purchased_product', 'get_product_reviews',
    'can_review_product', 'get_message_products', ...availableTriggers]) await load(name);
  if (definitions.has('rls_auto_enable')) await load('rls_auto_enable');
  else await db.exec(`create function public.rls_auto_enable() returns event_trigger language plpgsql
    security definer set search_path=pg_catalog as $$ begin return; end $$;`);
  // نحاكي المنح الصريحة والافتراضية التي تظهر في تصدير الإنتاج.
  await db.exec('grant execute on all functions in schema public to public, anon, authenticated');
  await db.exec(`
    create trigger guard_profile before update on public.profiles for each row execute function public.guard_profile_columns();
    create trigger guard_review before update on public.product_reviews for each row execute function public.product_reviews_guard();
    create trigger stamp_category before insert or update on public.category_images for each row execute function public.category_images_stamp();
    create trigger guard_message before update on public.messages for each row execute function public.guard_message_columns();
    create trigger touch_conversation after insert on public.messages for each row execute function public.touch_conversation_from_message();
    create event trigger auto_rls_fixture on ddl_command_end when tag in ('CREATE TABLE')
      execute function public.rls_auto_enable();
  `);
  await check('reproduce purchase-information exposure using synthetic data only', async () => {
    assert.equal((await asRole('anon',null,'select * from public.orders')).rows.length,0);
    assert.equal((await asRole('anon',null,'select public.has_purchased_product(1,$1) as bought',[member])).rows[0].bought,true);
  });
  await check('migration is repeatable and preserves every function body', async () => {
    const query = "select p.oid, p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by p.oid";
    const before=(await db.query(query)).rows;
    await db.exec(fix); await db.exec(fix);
    assert.deepEqual((await db.query(query)).rows,before);
  });
  await check('purchase helper is inaccessible directly to visitors and members', async () => {
    for(const [role,uid] of [['anon',null],['authenticated',member],['authenticated',other]]) {
      await assert.rejects(() => asRole(role,uid,'select public.has_purchased_product(1,$1)',[member]),e=>e.code==='42501');
    }
  });
  await check('public reviews still return true and false verified-buyer badges', async () => {
    for(const [role,uid] of [['anon',null],['authenticated',member]]) {
      const {rows}=await asRole(role,uid,'select * from public.get_product_reviews(1,20,0)');
      assert.equal(rows.length,2);
      assert.equal(rows.find(x=>x.author_name==='Buyer').is_verified,true);
      assert.equal(rows.find(x=>x.author_name==='Other').is_verified,false);
    }
  });
  await check('personal review status requires login and preserves own-review result', async () => {
    await assert.rejects(()=>asRole('anon',null,'select * from public.can_review_product(1)'),e=>e.code==='42501');
    const {rows}=await asRole('authenticated',member,'select * from public.can_review_product(1)');
    assert.deepEqual(rows,[{can_review:true,has_review:true}]);
  });
  await check('message products require login and remain limited to conversation parties', async () => {
    await assert.rejects(()=>asRole('anon',null,'select * from public.get_message_products(1)'),e=>e.code==='42501');
    for(const [uid,count] of [[member,1],[factoryOwner,1],[other,0]]) {
      assert.equal((await asRole('authenticated',uid,'select * from public.get_message_products(1)')).rows.length,count);
    }
  });
  await check('trigger and event-trigger functions have no direct client EXECUTE grants', async () => {
    const {rows}=await db.query(`select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prosecdef and p.prorettype in ('trigger'::regtype,'event_trigger'::regtype)
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))`);
    assert.equal(rows.length,0);
  });
  await check('profile trigger still prevents self-promotion while allowing name edits', async () => {
    const {rows}=await asRole('authenticated',member,
      "update public.profiles set is_admin=true,account_type='factory',full_name='New name' where id=$1 returning *",[member]);
    assert.equal(rows[0].is_admin,false); assert.equal(rows[0].account_type,'individual');
    assert.equal(rows[0].full_name,'New name');
  });
  await check('review and message triggers still protect immutable fields', async () => {
    const review=await asRole('authenticated',member,
      'update public.product_reviews set author_id=$1,product_id=99,rating=3 where author_id=$2 returning *',[other,member]);
    assert.equal(review.rows[0].author_id,member); assert.equal(review.rows[0].product_id,1);
    assert.equal(review.rows[0].rating,3);
    const message=await asRole('authenticated',factoryOwner,
      "update public.messages set body='Changed',is_read=true where id=1 returning *");
    assert.equal(message.rows[0].body,'Original'); assert.equal(message.rows[0].is_read,true);
  });
  await check('category audit and conversation timestamp triggers still run', async () => {
    const category=await asRole('authenticated',member,
      "insert into public.category_images(category_id,image_url) values('test','https://example.test/c.webp') returning *");
    assert.equal(category.rows[0].updated_by,member); assert(category.rows[0].updated_at);
    await db.exec(`insert into public.messages(id,conversation_id,sender_id,body) values (2,1,'${member}','Next')`);
    assert(new Date((await db.query('select last_message_at from public.conversations where id=1')).rows[0].last_message_at).getFullYear()>2000);
  });
  await check('event trigger remains bound and can run after its client grants are revoked', async () => {
    await db.exec('create table public.rls_after_fix(id integer)');
    const {rows}=await db.query("select relrowsecurity from pg_class where oid='public.rls_after_fix'::regclass");
    if(snapshot) assert.equal(rows[0].relrowsecurity,true);
    assert.equal((await db.query("select count(*)::int as n from pg_event_trigger where evtname='auto_rls_fixture'")).rows[0].n,1);
  });
  await check('unexpected policy dependencies cause an atomic refusal', async () => {
    await db.exec(`create policy unexpected_purchase_dependency on public.orders for select to authenticated
      using(public.has_purchased_product(1,buyer_id));`);
    await assert.rejects(()=>db.exec(fix), /Review policy dependencies/);
    await db.exec('rollback');
    await db.exec('drop policy unexpected_purchase_dependency on public.orders');
  });
  console.log(`Completed ${checks} checks${snapshot ? ' using exported production function definitions' : ''}. No production data accessed.`);
} finally { await db.close(); }
