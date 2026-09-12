// PostgreSQL معزول: اختبار تقييد قائمة الملفات مع سياسات الرفع والحذف الحالية.
// node scripts/test_storage_listing.mjs <temporary-pglite-package-directory>
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

if (!process.argv[2]) throw new Error('Pass the isolated PGlite package directory.');
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const admin = '10000000-0000-4000-8000-000000000001';
const member = '20000000-0000-4000-8000-000000000001';
const other = '20000000-0000-4000-8000-000000000002';
let checks = 0;
async function check(name, fn) { await fn(); console.log(`PASS ${name}`); checks++; }
async function asRole(role, uid, fn) {
  assert(['anon', 'authenticated'].includes(role));
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    const result = await fn(db);
    await db.exec('commit');
    return result;
  } catch (error) { await db.exec('rollback'); throw error; }
}
const migration = name => readFile(new URL(`../supabase/migrations/${name}.sql`, import.meta.url), 'utf8');
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema storage;
    grant usage on schema public, auth, storage to anon, authenticated;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create table public.profiles (id uuid primary key, is_admin boolean not null);
    insert into public.profiles values ('${admin}', true), ('${member}', false), ('${other}', false);
    create function public.is_admin() returns boolean language sql stable security definer
      set search_path = public as
      $$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;
    create function public.touch_updated_at() returns trigger language plpgsql
      set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
    create table storage.buckets (id text primary key, name text, public boolean default false,
      file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(),
      bucket_id text references storage.buckets, name text not null, owner_id text,
      unique(bucket_id, name));
    create function storage.foldername(name text) returns text[] language sql immutable as
      $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1)-1] $$;
    alter table storage.objects enable row level security;
    grant select, insert, update, delete on storage.objects to anon, authenticated;
    insert into storage.buckets(id,name,public) values
      ('factory-media','factory-media',true),('chat-media','chat-media',false);
    create policy chat_fixture_read on storage.objects for select to authenticated
      using (bucket_id='chat-media' and owner_id=auth.uid()::text);
  `);
  const foundation = await migration('20260827180000_backend_foundation');
  for (const name of ['factory_media_public_read', 'factory_media_owner_insert',
    'factory_media_owner_update', 'factory_media_owner_delete']) {
    const statement = foundation.match(new RegExp(`create policy ${name} on storage.objects[\\s\\S]*?;`));
    assert(statement, `Missing existing policy ${name}`);
    await db.exec(statement[0]);
  }
  await db.exec(await migration('20260910020000_home_promotions'));
  await db.exec(await migration('20260911090000_home_video_promotions'));
  for (const bucket of ['factory-media', 'promotion-media', 'video-promotion-media', 'chat-media']) {
    for (const uid of [admin, member, other]) {
      await db.query('insert into storage.objects(bucket_id,name,owner_id) values ($1,$2,$3)',
        [bucket, `${uid}/media/cover.webp`, uid]);
    }
  }
  await db.query('insert into storage.objects(bucket_id,name,owner_id) values ($1,$2,$3)',
    ['factory-media', 'legacy-path/cover.webp', member]);
  const fix = await migration('20260912130000_restrict_storage_listing');
  await check('migration is repeatable and preserves files and public bucket flags', async () => {
    await db.exec(fix); await db.exec(fix);
    assert.equal((await db.query('select * from storage.objects')).rows.length, 13);
    const buckets = (await db.query('select id, public from storage.buckets')).rows;
    assert(buckets.filter(x => x.id !== 'chat-media').every(x => x.public));
    assert.equal(buckets.find(x => x.id === 'chat-media').public, false);
  });
  await check('visitors cannot enumerate any of the protected buckets', async () => {
    const { rows } = await asRole('anon', null, tx => tx.query('select * from storage.objects'));
    assert.equal(rows.length, 0);
  });
  await check('members see only their factory files, including owned legacy paths', async () => {
    const { rows } = await asRole('authenticated', member, tx => tx.query(
      "select * from storage.objects where bucket_id <> 'chat-media'"));
    assert.equal(rows.length, 2);
    assert(rows.every(x => x.bucket_id === 'factory-media' && x.owner_id === member));
  });
  await check('admin retains media management visibility', async () => {
    const { rows } = await asRole('authenticated', admin, tx => tx.query(
      "select * from storage.objects where bucket_id <> 'chat-media'"));
    assert.equal(rows.length, 10);
  });
  await check('factory uploads, updates and cleanup still work for their owner only', async () => {
    const file = `${member}/media/new.webp`;
    await asRole('authenticated', member, tx => tx.query(
      "insert into storage.objects(bucket_id,name,owner_id) values('factory-media',$1,$2)", [file, member]));
    const { rows: forbidden } = await asRole('authenticated', other, tx => tx.query(
      "delete from storage.objects where bucket_id='factory-media' and name=$1 returning id", [file]));
    assert.equal(forbidden.length, 0);
    const { rows: updated } = await asRole('authenticated', member, tx => tx.query(
      "update storage.objects set name=$1 where bucket_id='factory-media' and name=$1 returning id", [file]));
    assert.equal(updated.length, 1);
    const { rows: removed } = await asRole('authenticated', member, tx => tx.query(
      "delete from storage.objects where bucket_id='factory-media' and name=$1 returning id", [file]));
    assert.equal(removed.length, 1);
  });
  await check('ad uploads and unreferenced cleanup still work; published covers stay protected', async () => {
    for (const [bucket, table] of [['promotion-media','home_promotions'], ['video-promotion-media','home_video_promotions']]) {
      const file = `${admin}/media/new.webp`;
      await asRole('authenticated', admin, tx => tx.query(
        'insert into storage.objects(bucket_id,name,owner_id) values ($1,$2,$3)', [bucket,file,admin]));
      const url = `https://example.supabase.co/storage/v1/object/public/${bucket}/${file}`;
      const ad = await asRole('authenticated', admin, tx => tx.query(
        `insert into public.${table}(title,image_url${table === 'home_video_promotions' ? ',video_url' : ''})
         values('Ad',$1${table === 'home_video_promotions' ? ', $2' : ''}) returning id`,
        table === 'home_video_promotions' ? [url,url.replace('.webp','.mp4')] : [url]));
      const blocked = await asRole('authenticated', admin, tx => tx.query(
        'delete from storage.objects where bucket_id=$1 and name=$2 returning id', [bucket,file]));
      assert.equal(blocked.rows.length, 0);
      await asRole('authenticated', admin, tx => tx.query(`delete from public.${table} where id=$1`,[ad.rows[0].id]));
      const removed = await asRole('authenticated', admin, tx => tx.query(
        'delete from storage.objects where bucket_id=$1 and name=$2 returning id',[bucket,file]));
      assert.equal(removed.rows.length, 1);
    }
  });
  await check('unrelated private bucket keeps its existing visibility', async () => {
    const { rows } = await asRole('authenticated', member, tx => tx.query(
      "select * from storage.objects where bucket_id='chat-media'"));
    assert.equal(rows.length, 1); assert.equal(rows[0].owner_id, member);
  });
  await check('a separate broad SELECT policy cannot reopen protected listings', async () => {
    await db.exec('create policy broad_select_fixture on storage.objects for select to public using (true)');
    for (const [role,uid,count] of [['anon',null,0], ['authenticated',member,2]]) {
      const { rows } = await asRole(role,uid,tx => tx.query(
        "select * from storage.objects where bucket_id in ('factory-media','promotion-media','video-promotion-media')"));
      assert.equal(rows.length,count);
    }
    await db.exec('drop policy broad_select_fixture on storage.objects');
  });
  console.log(`Completed ${checks} storage listing checks. No production data accessed.`);
} finally { await db.close(); }
