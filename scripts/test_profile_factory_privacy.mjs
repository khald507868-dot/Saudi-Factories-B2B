// قاعدة في الذاكرة فقط. المعامل الثالث اختياري: تصدير تعريفات الإنتاج بصيغة CSV.
// node scripts/test_profile_factory_privacy.mjs <pglite-directory> [diagnostic.csv]
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite} = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const read = f => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
function csv(text) {
  const rows = []; let row = [], value = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { value += '"'; i++; }
      else quoted = !quoted;
    } else if (c === ',' && !quoted) { row.push(value); value = ''; }
    else if ((c === '\n' || c === '\r') && !quoted) {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(value); rows.push(row); row = []; value = '';
    } else value += c;
  }
  assert(!quoted, 'Unclosed CSV field');
  if (value || row.length) { row.push(value); rows.push(row); }
  const headers = rows.shift(); headers[0] = headers[0].replace(/^\uFEFF/, '');
  return rows.filter(r => r.length > 1).map(r => Object.fromEntries(headers.map((h, i) => [h, r[i]])));
}
const exported = process.argv[3] ? csv(readFileSync(resolve(process.argv[3]), 'utf8')) : [];
const defs = new Map();
for (const file of ['schema.sql', 'supabase/migrations/20260829100000_realtime_messages.sql',
  'supabase/migrations/20260829110000_message_unread_counts.sql',
  'supabase/migrations/20260908120000_product_reviews.sql',
  'supabase/migrations/20260908150000_rating_breakdown.sql',
  'supabase/migrations/20260908180000_open_reviews.sql',
  'supabase/migrations/20260913210000_account_approval_gate.sql']) {
  for (const m of read(file).matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\([\s\S]*?\bas\s+(\$[a-zA-Z0-9_]*\$)[\s\S]*?\2\s*;/gi)) defs.set(m[1], m[0]);
}
for (const r of exported.filter(r => r.object_type === 'function')) defs.set(r.object_name.replace(/^public\./, '').split('(')[0], r.definition);
const db = new PGlite();
const uid = n => `80000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
let checks = 0;
async function check(name, fn) { await fn(); checks++; console.log('PASS ' + name); }
async function as(n, sql, args = [], role = n ? 'authenticated' : 'anon') {
  await db.exec('begin; set local role ' + role);
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)", [n ? uid(n) : '', role]);
    const result = await db.query(sql, args); await db.exec('commit'); return result.rows;
  } catch (e) { await db.exec('rollback'); throw e; }
}
async function policy(table, name, fallback) {
  const r = exported.find(r => r.object_type === 'policy' && r.object_name === `${table} / ${name}`);
  if (!r) { assert(!exported.length, 'Missing exported policy: ' + name); await db.exec(fallback); return; }
  const d = JSON.parse(r.details), m = r.definition.match(/^USING: ([\s\S]*)\nWITH CHECK: ([\s\S]*)$/);
  assert(m); assert(['ALL','SELECT','INSERT','UPDATE','DELETE'].includes(d.command));
  const roles = d.roles.map(r => r === 'public' ? 'public' : `"${r}"`).join(',');
  await db.exec(`create policy ${name} on ${table} as ${d.permissive} for ${d.command} to ${roles}` +
    (m[1] === '(none)' ? '' : ` using (${m[1]})`) + (m[2] === '(none)' ? '' : ` with check (${m[2]})`));
}
const upload = (user, factory) => as(user, "insert into storage.objects(bucket_id,name) values('factory-certificates',$1)", [`${uid(user)}/certificates/${factory}/test.png`]);
try {
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth; create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin boolean,full_name text,email text,phone text,birthdate date,company_image text);
    create table factories(id bigint primary key,owner_id uuid,name text,status text,address_city text,logo text);
    create table products(id bigint primary key,factory_id bigint);
    create table conversations(id bigint primary key,factory_id bigint,individual_id uuid,kind text default 'inquiry',last_message_at timestamptz default now(),created_at timestamptz default now());
    create table messages(id bigint primary key,conversation_id bigint,sender_id uuid,body text,attachment_type text,created_at timestamptz default now(),read_at timestamptz);
    create table product_reviews(id bigint primary key,product_id bigint,author_id uuid,rating smallint,body text,created_at timestamptz default now());
    create table orders(id uuid primary key,buyer_id uuid,status text);
    create table order_items(order_id uuid,product_id bigint);
    create table storage.objects(bucket_id text,name text);
    grant usage on schema public,auth,storage to anon,authenticated;
    grant select on all tables in schema public to anon,authenticated;
    grant update on profiles to authenticated;
    grant insert on storage.objects to authenticated;
  `);
  for (let n = 1; n <= 7; n++) {
    await db.query('insert into auth.users values($1,$2)', [uid(n), n === 7 ? null : '2026-09-17']);
    await db.query('insert into profiles values($1,$2,$3,$4,$5,$6,$7,$8)', [uid(n), [1,5,6,7].includes(n) ? 'factory' : 'individual', n === 4, `User ${n}`, `private-${n}@example.invalid`, `private-phone-${n}`, '2000-01-01', `https://example.invalid/${n}.png`]);
  }
  await db.query("insert into factories values(1,$1,'Approved factory','approved','Public city','logo'),(2,$2,'Pending factory','pending','Hidden city 2','logo'),(3,$3,'Rejected factory','rejected','Hidden city 3','logo'),(4,$4,'Unconfirmed factory','approved','Public city','logo')", [uid(1),uid(5),uid(6),uid(7)]);
  await db.exec('insert into products values(1,1),(2,2),(3,3),(4,2)');
  await db.query('insert into conversations(id,factory_id,individual_id) values(1,1,$1)', [uid(2)]);
  await db.query("insert into messages(id,conversation_id,sender_id,body,attachment_type) values(1,1,$1,'Hello','')", [uid(2)]);
  await db.query("insert into product_reviews(id,product_id,author_id,rating,body) values(1,1,$1,5,'Review')", [uid(2)]);
  await db.query("insert into orders values($1,$2,'paid');", [uid(100),uid(2)]);
  await db.query('insert into order_items values($1,1)', [uid(100)]);
  for (const name of ['is_admin','owns_factory','in_conversation','account_can_write','guard_profile_columns','has_purchased_product','get_factory_summary','get_conversation_peers','get_conversation_summaries','get_product_reviews']) {
    assert(defs.has(name), 'Missing function: ' + name); await db.exec(defs.get(name));
  }
  await db.exec(`create trigger profiles_guard before update on profiles for each row execute function guard_profile_columns();
    revoke execute on function has_purchased_product(bigint,uuid) from public,anon,authenticated;
    revoke execute on function get_conversation_peers(),get_conversation_summaries() from public,anon;
    grant execute on function get_conversation_peers(),get_conversation_summaries() to authenticated;`);
  for (const table of ['public.profiles','public.factories','public.products','public.conversations','public.messages','storage.objects']) await db.exec(`alter table ${table} enable row level security`);
  await policy('public.profiles','profiles_select_own', 'create policy profiles_select_own on profiles for select using(id=auth.uid() or is_admin())');
  await policy('public.profiles','profiles_select_conversation_party', `create policy profiles_select_conversation_party on profiles for select using(id=auth.uid() or exists(select 1 from conversations c join factories f on f.id=c.factory_id where c.individual_id=profiles.id and (c.individual_id=auth.uid() or f.owner_id=auth.uid())) or is_admin())`);
  await policy('public.profiles','profiles_update_own', 'create policy profiles_update_own on profiles for update using(id=auth.uid()) with check(id=auth.uid())');
  await policy('public.factories','factories_select_public', "create policy factories_select_public on factories for select using(status='approved' or owner_id=auth.uid() or is_admin())");
  await policy('public.products','products_select_public', "create policy products_select_public on products for select using(exists(select 1 from factories f where f.id=products.factory_id and (f.status='approved' or f.owner_id=auth.uid() or is_admin())))");
  await policy('public.conversations','conversations_select_party', 'create policy conversations_select_party on conversations for select using(individual_id=auth.uid() or owns_factory(factory_id))');
  await policy('public.messages','messages_select_party', 'create policy messages_select_party on messages for select using(in_conversation(conversation_id))');
  await policy('storage.objects','factory_certificates_storage_add', "create policy factory_certificates_storage_add on storage.objects for insert to authenticated with check(bucket_id='factory-certificates' and split_part(name,'/',1)=auth.uid()::text and split_part(name,'/',2)='certificates' and account_can_write() and exists(select 1 from factories f where f.id::text=split_part(name,'/',3) and f.owner_id=auth.uid() and f.status='approved'))");
  await check('reproduce complete conversation-customer profile disclosure', async () => {
    const [p] = await as(1, 'select email,phone,birthdate from profiles where id=$1', [uid(2)]);
    assert.equal(p.email, 'private-2@example.invalid'); assert.equal(p.phone, 'private-phone-2'); assert(p.birthdate);
  });
  await check('reproduce hidden-factory metadata disclosure through the definer', async () => {
    for (const actor of [0,2]) {
      assert.equal((await as(actor, 'select * from factories where id=2')).length, 0);
      const [row] = await as(actor, 'select * from get_factory_summary(2)');
      assert.equal(row.city, 'Hidden city 2'); assert.equal(Number(row.product_count), 2);
    }
  });
  await check('reproduce certificate upload denial and wrong-folder allowance due to factory-name shadowing', async () => {
    await assert.rejects(() => upload(1,1), e => e.code === '42501');
    await db.exec("update factories set name='crafted/name/1' where id=1");
    await upload(1,999);
    await db.exec("update factories set name='Approved factory' where id=1");
  });
  const fix = read('supabase/migrations/20260917120000_profile_factory_privacy.sql');
  const before = (await db.query('select * from profiles order by id')).rows;
  await check('migration is repeatable and preserves user and storage records', async () => {
    await db.exec(fix); await db.exec(fix);
    assert.deepEqual((await db.query('select * from profiles order by id')).rows, before);
    assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,1);
  });
  await check('own/admin profiles remain accessible while customer profiles stay private even with a broad policy', async () => {
    await db.exec('create policy unexpected_broad_read on profiles for select using(true)');
    assert.equal((await as(1, 'select * from profiles where id=$1', [uid(2)])).length, 0);
    assert.equal((await as(0, 'select * from profiles')).length, 0);
    assert.equal((await as(2, 'select * from profiles')).length, 1);
    assert.equal((await as(4, 'select * from profiles')).length, 7);
    await as(2, "update profiles set full_name='Updated',is_admin=true where id=$1", [uid(2)]);
    const [own] = await as(2, 'select full_name,is_admin from profiles where id=$1', [uid(2)]);
    assert.equal(own.full_name, 'Updated'); assert.equal(own.is_admin, false);
  });
  await check('chat names, previews, unread counts and review attribution remain available without contact details', async () => {
    const [peer] = await as(1, 'select * from get_conversation_peers()');
    assert.equal(peer.peer_name, 'Updated'); assert(!('email' in peer)); assert(!('phone' in peer));
    const [summary] = await as(1, 'select * from get_conversation_summaries()');
    assert.equal(summary.last_message_body, 'Hello'); assert.equal(Number(summary.unread_count), 1);
    assert.equal((await as(2, 'select * from get_conversation_peers()'))[0].peer_name, 'Approved factory');
    assert.equal((await as(3, 'select * from get_conversation_peers()')).length, 0);
    for (const actor of [0,1,2]) {
      const [review] = await as(actor, 'select * from get_product_reviews(1)');
      assert.equal(review.author_name, 'Updated'); assert.equal(review.is_verified, true);
    }
  });
  await check('summary follows RLS for visitors, unrelated users, owners and administrators', async () => {
    for (const actor of [0,1,2,3]) {
      assert.equal((await as(actor, 'select * from get_factory_summary(1)')).length, 1);
      for (const id of [2,3,999]) assert.equal((await as(actor, 'select * from get_factory_summary($1)', [id])).length, 0);
    }
    assert.equal((await as(5, 'select * from get_factory_summary(2)'))[0].city, 'Hidden city 2');
    assert.equal((await as(6, 'select * from get_factory_summary(3)'))[0].city, 'Hidden city 3');
    assert.equal(Number((await as(4, 'select * from get_factory_summary(2)'))[0].product_count), 2);
    const [meta] = (await db.query("select prosecdef,has_function_privilege('anon',oid,'execute') as anon_execute from pg_proc where proname='get_factory_summary'")).rows;
    assert.equal(meta.prosecdef, false); assert.equal(meta.anon_execute, true);
  });
  await check('certificate uploads use the object path and reject foreign, nonexistent or unapproved factories', async () => {
    await upload(1,1);
    for (const [actor, factory] of [[1,2],[1,999],[2,1],[5,2],[6,3],[7,4]]) await assert.rejects(() => upload(actor,factory), e => e.code === '42501');
    await db.exec("update factories set name='crafted/name/1' where id=1");
    await assert.rejects(() => upload(1,999), e => e.code === '42501');
    await upload(1,1);
  });
  await check('migration refuses disabled RLS', async () => {
    const diagnostic = await db.query(read('supabase/diagnostics/profile_factory_privacy_verify.sql'));
    assert.equal(diagnostic.rows.length, 6);
    assert(diagnostic.rows.every(r => r.passed === true), JSON.stringify(diagnostic.rows));
    await db.exec('alter table products disable row level security');
    await assert.rejects(() => db.exec(fix), /Enable and review RLS/); await db.exec('rollback');
  });
  console.log(`Completed ${checks} checks (${exported.length ? 'exported production definitions' : 'local definitions'}); synthetic data only.`);
} finally { await db.close(); }
