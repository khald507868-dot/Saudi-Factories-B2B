import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const uid = n => `10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
try {
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth; create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin bool default false);
    create table factories(id int primary key,owner_id uuid,status text,rejection_reason text);
    create table messages(id int generated always as identity,body text);
    create table storage.objects(id int generated always as identity,name text);
    alter table storage.objects enable row level security;
    create policy upload_own on storage.objects for all to authenticated using(true) with check(true);
    grant usage on schema auth,public,storage to authenticated,anon,service_role;
    grant all on all tables in schema public,storage to authenticated;
    grant usage on all sequences in schema public,storage to authenticated;
    create function is_admin() returns bool language sql security definer set search_path=public as $$select coalesce((select is_admin from profiles where id=auth.uid()),false)$$;
    create function write_message() returns void language sql security definer set search_path=public as $$insert into messages(body) values('RPC')$$;
  `);
  for (let n=1;n<=5;n++) {
    await db.query('insert into auth.users values($1,$2)', [uid(n), n===1?null:'2026-09-13']);
    await db.query('insert into profiles values($1,$2,$3)', [uid(n), n===1||n===2?'individual':'factory',n===5]);
  }
  await db.query("insert into factories values(3,$1,'pending',null),(4,$2,'approved',null),(5,$3,'pending',null)",[uid(3),uid(4),uid(5)]);
  const schema=readFileSync(new URL('../schema.sql',import.meta.url),'utf8');
  const factoryGuard=schema.match(/create or replace function public.guard_factory_columns\(\)[\s\S]*?\$fn\$;/)[0];
  await db.exec(factoryGuard+ ' create trigger factories_guard before update on factories for each row execute function guard_factory_columns();');
  const migration=readFileSync(new URL('../supabase/migrations/20260913210000_account_approval_gate.sql',import.meta.url),'utf8');
  await db.exec(migration); await db.exec(migration);
  async function as(n,sql,role='authenticated') {
    await db.exec('begin; set local role authenticated;');
    try {
      await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[uid(n),role]);
      const r=await db.query(sql); await db.exec('commit'); return r;
    } catch(e) { await db.exec('rollback'); throw e; }
  }
  for(const n of [1,3]) {
    for(const sql of ["insert into messages(body) values('blocked')",'select write_message()',"insert into storage.objects(name) values('blocked')"]) {
      await assert.rejects(()=>as(n,sql),e=>e.code==='42501');
    }
  }
  console.log('PASS unconfirmed individuals and pending factories cannot write directly, through a definer RPC, or upload');
  for(const n of [2,4,5]) await as(n,"insert into messages(body) values('allowed')");
  await assert.rejects(()=>as(3,"update factories set status='approved' where id=3"),e=>e.code==='42501');
  await as(5,"update factories set status='approved' where id=3");
  await as(3,"insert into messages(body) values('approved now')");
  await as(5,"update factories set status='rejected' where id=3");
  await assert.rejects(()=>as(3,'select write_message()'),e=>e.code==='42501');
  console.log('PASS only admin can approve; approval unlocks writes and rejection blocks existing sessions');
  await db.query('insert into profiles values($1,$2,false)',[uid(6),'individual']);
  console.log('PASS server registration without user JWT and repeat migration remain valid');
} finally { await db.close(); }
