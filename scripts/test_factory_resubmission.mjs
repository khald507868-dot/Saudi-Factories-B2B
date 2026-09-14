import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const uid = n => `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth; create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin bool default false);
    create table messages(id int generated always as identity,body text);
    create table storage.objects(id int generated always as identity,name text);
    alter table storage.objects enable row level security;
    create policy upload_own on storage.objects for all to authenticated using(true) with check(true);
    create function public.is_admin() returns bool language sql security definer set search_path='' as
      $$select coalesce((select is_admin from public.profiles where id=auth.uid()),false)$$;
  `);
  const schema = read('schema.sql');
  await db.exec(schema.match(/create table if not exists public.factories \([\s\S]*?\n\);/)[0]);
  await db.exec(schema.match(/create or replace function public.guard_factory_columns\(\)[\s\S]*?\$fn\$;/)[0]);
  await db.exec(`create trigger factories_guard before update on factories for each row execute function public.guard_factory_columns();
    alter table factories enable row level security;
    create policy factory_owner on factories for all to authenticated using(owner_id=auth.uid() or public.is_admin()) with check(owner_id=auth.uid() or public.is_admin());
    grant usage on schema auth,public,storage to authenticated,anon;
    grant all on all tables in schema public,storage to authenticated;
    grant usage on all sequences in schema public,storage to authenticated;
  `);
  for (let n = 1; n <= 5; n++) {
    await db.query('insert into auth.users values($1,$2)', [uid(n), n === 1 ? null : '2026-09-13']);
    await db.query('insert into profiles values($1,$2,$3)', [uid(n), n === 2 ? 'individual' : 'factory', n === 5]);
    await db.query("insert into factories(owner_id,status,name,commercial_register,industrial_license,rejection_reason) values($1,'rejected','Factory','1234','4321','Wrong license')", [uid(n)]);
  }
  await db.exec(read('supabase/migrations/20260913210000_account_approval_gate.sql'));
  const migration = read('supabase/migrations/20260914090000_factory_application_resubmission.sql');
  await db.exec(migration); await db.exec(migration);
  async function as(n, sql, params = []) {
    await db.exec('begin; set local role authenticated;');
    try {
      await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)", [n ? uid(n) : '']);
      const result = await db.query(sql, params); await db.exec('commit'); return result;
    } catch (e) { await db.exec('rollback'); throw e; }
  }
  const rpc = (n, details) => as(n, 'select public.resubmit_factory_application($1::jsonb) as result', [JSON.stringify(details)]);
  for (const n of [0, 1, 2]) await assert.rejects(() => rpc(n, { industrial_license: '9876543210' }), e => e.code === '42501');
  for (const details of [null, [], { owner_id: uid(4) }, { status: 'approved' }, { cover: 'fake' }, { name: '' }, { industrial_license: 'ABC' }, { commercial_register: '12345678901' }]) {
    await assert.rejects(() => rpc(3, details), e => e.code === '22023');
  }
  await assert.rejects(() => as(3, "update factories set status='approved' where owner_id=auth.uid()"), e => e.code === '42501');
  await assert.rejects(() => as(3, "update factories set status='pending', rejection_reason='', cover='fake' where owner_id=auth.uid()"), e => e.code === '42501');
  await assert.rejects(() => as(3, "select public.is_factory_resubmission('{}','{}')"), e => e.code === '42501');
  const result = await rpc(3, { industrial_license: '9876543210', address_city: 'Riyadh' });
  assert.equal(result.rows[0].result.status, 'pending');
  const rows = (await db.query('select owner_id,status,industrial_license,address_city,rejection_reason from factories order by id')).rows;
  assert.equal(rows[2].owner_id, uid(3));
  assert.equal(rows[2].industrial_license, '9876543210');
  assert.equal(rows[2].address_city, 'Riyadh');
  assert.equal(rows[2].rejection_reason, '');
  assert.equal(rows[3].status, 'rejected');
  assert.equal(rows[3].industrial_license, '4321');
  assert.equal((await db.query('select email_confirmed_at is not null as confirmed from auth.users where id=$1', [uid(3)])).rows[0].confirmed, true);
  await assert.rejects(() => rpc(3, { industrial_license: '111' }), /application_not_rejected/);
  for (const sql of ["insert into messages(body) values('blocked')", "insert into storage.objects(name) values('blocked')", "update profiles set is_admin=true where id=auth.uid()", "delete from factories where owner_id=auth.uid()"]) {
    await assert.rejects(() => as(3, sql), e => e.code === '42501');
  }
  await as(5, "update factories set status='approved' where owner_id='" + uid(3) + "'");
  await as(3, "insert into messages(body) values('approved')");
  await assert.rejects(() => rpc(3, { industrial_license: '111' }), /application_not_rejected/);
  assert.equal((await db.query("select has_function_privilege('anon','public.resubmit_factory_application(jsonb)','execute') as allowed")).rows[0].allowed, false);
  console.log('PASS owner-only resubmission, field validation, no self-approval, no unrelated writes, unchanged confirmed email, pending lock, admin approval and repeat migration');
} finally { await db.close(); }
