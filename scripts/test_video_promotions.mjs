// اختبار ترحيل الإعلانات وسياسات RLS في PostgreSQL معزول؛ لا يتصل بقاعدة الموقع.
// ثبّت @electric-sql/pglite في مجلد مؤقت ثم مرّر مساره كأول وسيط.
// node scripts/test_home_promotions.mjs <temporary-package-directory>
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

if (!process.argv[2]) throw new Error('Pass the isolated PGlite package directory.');
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))(
  '@electric-sql/pglite',
);
const db = new PGlite();
const admin = '10000000-0000-4000-8000-000000000001';
const otherAdmin = '10000000-0000-4000-8000-000000000002';
const member = '20000000-0000-4000-8000-000000000001';
const active = '30000000-0000-4000-8000-000000000001';
const hidden = '30000000-0000-4000-8000-000000000002';
const draft = '30000000-0000-4000-8000-000000000003';
const image = (owner, name) =>
  `https://example.supabase.co/storage/v1/object/public/video-promotion-media/${owner}/promotions/${name}.webp`;
let checks = 0;

async function check(name, run) {
  await run();
  checks++;
  console.log(`PASS ${name}`);
}

async function asRole(role, uid, run) {
  assert(['anon', 'authenticated'].includes(role));
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    const result = await run(db);
    await db.exec('commit');
    return result;
  } catch (error) {
    await db.exec('rollback');
    throw error;
  }
}

async function denied(role, uid, sql, params = []) {
  await assert.rejects(
    () => asRole(role, uid, (tx) => tx.query(sql, params)),
    (error) => error.code === '42501',
  );
}

try {
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create schema storage;
    grant usage on schema public, auth, storage to anon, authenticated;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table public.profiles (id uuid primary key, is_admin boolean not null default false);
    insert into public.profiles values ('${admin}', true), ('${otherAdmin}', true), ('${member}', false);
    create function public.is_admin() returns boolean language sql stable
      security definer set search_path = public as
      $$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;
    create function public.touch_updated_at() returns trigger language plpgsql
      set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
    create table storage.buckets (
      id text primary key, name text not null, public boolean default false,
      file_size_limit bigint, allowed_mime_types text[]
    );
    create table storage.objects (
      id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
      name text not null, owner_id text, unique(bucket_id, name)
    );
    create function storage.foldername(name text) returns text[] language sql immutable as
      $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1)-1] $$;
    alter table storage.objects enable row level security;
    grant select, insert, update, delete on storage.objects to anon, authenticated;
    -- سياسة واسعة متعمدة: يجب ألا تسمح بتجاوز حواجز دلو الإعلانات.
    create policy deliberately_broad_storage on storage.objects
      for all to authenticated using (true) with check (true);
    insert into storage.buckets (id, name) values ('control-media', 'control-media');
  `);
  const migration = await readFile(new URL('../supabase/migrations/20260911090000_home_video_promotions.sql', import.meta.url), 'utf8');
  const video = image(admin, 'clip').replace('.webp', '.mp4');
  await check('migration is repeatable', async () => { await db.exec(migration); await db.exec(migration); });
  await check('video bucket MIME types and 50MB cap', async () => {
    const {rows} = await db.query("select * from storage.buckets where id='video-promotion-media'");
    assert.equal(Number(rows[0].file_size_limit), 52428800);
    assert(rows[0].allowed_mime_types.includes('video/mp4'));
    assert(rows[0].allowed_mime_types.includes('image/jpeg'));
  });
  await check('only admin publishes videos', async () => {
    await asRole('authenticated', admin, tx => tx.query(`insert into public.home_video_promotions
      (id,title,image_url,video_url,logo_url,is_active) values
      ($1,'Published',$2,$3,$4,true),($5,'Draft',$2,$3,$4,false)`,
      [active,image(admin,'cover'),video,image(admin,'logo'),hidden]));
    for (const [role,uid] of [['anon',null],['authenticated',member]]) {
      await denied(role,uid,'insert into public.home_video_promotions(title,image_url,video_url) values ($1,$2,$3)',
        ['Not allowed',image(admin,'cover'),video]);
      const {rows}=await asRole(role,uid,tx=>tx.query('select id from public.home_video_promotions'));
      assert.deepEqual(rows.map(r=>r.id),[active]);
    }
    const {rows}=await asRole('authenticated',admin,tx=>tx.query('select id from public.home_video_promotions'));
    assert.equal(rows.length,2);
  });
  await check('regular accounts cannot update or delete videos', async () => {
    for (const sql of ["update public.home_video_promotions set title='Changed' where id=$1 returning id",
      'delete from public.home_video_promotions where id=$1 returning id']) {
      const {rows}=await asRole('authenticated',member,tx=>tx.query(sql,[active]));
      assert.equal(rows.length,0);
    }
  });
  await check('SQL rejects image masquerading as video and unsafe target links', async () => {
    for (const [column,value] of [['video_url',image(admin,'cover')],['logo_url','https://external.test/logo.png'],
      ['target_url','javascript:alert(1)'],['sort_order',-1]]) {
      await assert.rejects(()=>asRole('authenticated',admin,tx=>tx.query(
        `update public.home_video_promotions set ${column}=$1 where id=$2`,[value,active])), e=>e.code==='23514');
    }
  });
  await check('upload requires admin even in presence of a broad storage policy', async () => {
    await denied('authenticated',member,'insert into storage.objects(bucket_id,name) values ($1,$2)',
      ['video-promotion-media',`${member}/videos/clip.mp4`]);
    await denied('authenticated',admin,'insert into storage.objects(bucket_id,name) values ($1,$2)',
      ['video-promotion-media',`${member}/videos/clip.mp4`]);
    await asRole('authenticated',admin,async tx=>{
      for (const name of ['cover.webp','clip.mp4','logo.webp','unused.mp4']) {
        await tx.query('insert into storage.objects(bucket_id,name) values ($1,$2)',
          ['video-promotion-media',`${admin}/promotions/${name}`]);
      }
    });
  });
  await check('referenced cover, video and logo cannot be deleted or overwritten', async () => {
    for (const name of ['cover.webp','clip.mp4','logo.webp']) {
      const {rows}=await asRole('authenticated',admin,tx=>tx.query(
        'delete from storage.objects where bucket_id=$1 and name=$2 returning id',
        ['video-promotion-media',`${admin}/promotions/${name}`]));
      assert.equal(rows.length,0);
    }
    const {rows}=await asRole('authenticated',admin,tx=>tx.query(
      "update storage.objects set owner_id='changed' where bucket_id='video-promotion-media' returning id"));
    assert.equal(rows.length,0);
  });
  await check('unreferenced own media can be cleaned up', async () => {
    const {rows}=await asRole('authenticated',admin,tx=>tx.query(
      'delete from storage.objects where bucket_id=$1 and name=$2 returning id',
      ['video-promotion-media',`${admin}/promotions/unused.mp4`]));
    assert.equal(rows.length,1);
  });
  await check('admin can hide, reorder and delete the ad', async () => {
    await asRole('authenticated',admin,async tx=>{
      const edited=await tx.query('update public.home_video_promotions set is_active=false,sort_order=4 where id=$1 returning *',[active]);
      assert.equal(edited.rows[0].sort_order,4);
      const deleted=await tx.query('delete from public.home_video_promotions where id=$1 returning id',[active]);
      assert.equal(deleted.rows.length,1);
    });
  });
  console.log(`${checks} video-ad database checks passed`);
} finally { await db.close(); }
