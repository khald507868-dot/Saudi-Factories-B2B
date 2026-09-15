// Isolated database: no real factory images or accounts are modified.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite}=createRequire(resolve(process.argv[2],'package.json'))('@electric-sql/pglite');
const db=new PGlite();
const read=f=>readFileSync(new URL('../'+f,import.meta.url),'utf8');
const uid=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
async function as(n,sql,args=[],role='authenticated') {
  await db.exec('begin;set local role '+role);
  try { await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[n?uid(n):'',role]);
    const r=await db.query(sql,args);await db.exec('commit');return r.rows;
  } catch(e) {await db.exec('rollback');throw e;}
}
const path=(n,f,name='one.png')=>`${uid(n)}/certificates/${f}/${name}`;
const upload=(n,f,p=path(n,f))=>as(n,"insert into storage.objects(bucket_id,name,metadata) values('factory-certificates',$1,'{\"mimetype\":\"image/png\"}')",[p]);
const add=(n,f,p=path(n,f))=>as(n,'insert into factory_certificates(factory_id,image_path) values($1,$2) returning id',[f,p]);
try {
  await db.exec(`create role authenticated;create role anon;create role service_role;create schema auth;create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin bool default false);
    create table factories(id bigint primary key,owner_id uuid,status text);
    create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(bucket_id text,name text,metadata jsonb);
    alter table storage.objects enable row level security;
    grant usage on schema public,auth,storage to anon,authenticated;
    grant select on factories to anon,authenticated;
    grant select,insert,delete on storage.objects to authenticated;
  `);
  for(let n=1;n<=4;n++) {
    await db.query('insert into auth.users values($1,$2)',[uid(n),n===4?null:'2026-09-15']);
    await db.query("insert into profiles values($1,'factory',false)",[uid(n)]);
    await db.query('insert into factories values($1,$2,$3)',[n,uid(n),n===3?'pending':'approved']);
  }
  await db.exec(read('supabase/migrations/20260913210000_account_approval_gate.sql'));
  const migration=read('supabase/migrations/20260915100000_factory_certificates.sql');
  await db.exec(migration);await db.exec(migration);
  await upload(1,1);const [row]=await add(1,1);
  assert.equal((await as(0,'select * from factory_certificates',[],'anon')).length,1);
  await assert.rejects(()=>upload(2,1));
  await assert.rejects(()=>upload(2,2,path(1,1,'stolen.png')));
  await assert.rejects(()=>add(2,1));
  await assert.rejects(()=>add(1,2));
  await assert.rejects(()=>add(1,1,path(1,1,'missing.png')),/certificate_image_required/);
  for(const [name,mime] of [['video.png','video/mp4'],['doc.pdf','image/png']]) {
    const p=path(1,1,name);
    await db.query("insert into storage.objects values('factory-certificates',$1,jsonb_build_object('mimetype',$2::text))",[p,mime]);
    await assert.rejects(()=>add(1,1,p),/certificate_image_required/);
  }
  for(const n of [3,4]) {await assert.rejects(()=>upload(n,n));await assert.rejects(()=>add(n,n));}
  assert.equal((await as(2,'delete from factory_certificates where id=$1 returning id',[row.id])).length,0);
  assert.equal((await as(2,"delete from storage.objects where name=$1 returning name",[path(1,1)])).length,0);
  await assert.rejects(()=>as(1,"update factory_certificates set image_path='other'"));
  await db.exec("update factories set status='pending' where id=1");
  assert.equal((await as(0,'select * from factory_certificates',[],'anon')).length,0);
  assert.equal((await as(1,'select * from factory_certificates')).length,1);
  await db.exec("update factories set status='approved' where id=1");
  assert.equal((await as(1,'delete from factory_certificates where id=$1 returning id',[row.id])).length,1);
  assert.equal((await as(1,'delete from storage.objects where name=$1 returning name',[path(1,1)])).length,1);
  const bucket=(await db.query('select * from storage.buckets')).rows[0];
  assert.equal(bucket.file_size_limit,5242880);assert.equal(bucket.public,true);
  assert.deepEqual(bucket.allowed_mime_types,['image/jpeg','image/png','image/webp']);
  console.log('PASS certificate ownership, public visibility, image paths/MIME, approval/email gates, storage isolation, deletion, and repeatable migration');
} finally {await db.close();}
