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
  `https://example.supabase.co/storage/v1/object/public/promotion-media/${owner}/promotions/${name}.webp`;
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
  const migration = await readFile(new URL(
    '../supabase/migrations/20260910020000_home_promotions.sql', import.meta.url,
  ), 'utf8');
  await check('migration applies twice without errors', async () => {
    await db.exec(migration);
    await db.exec(migration);
  });
  await check('bucket is public and limits image uploads to 5MB', async () => {
    const { rows } = await db.query("select * from storage.buckets where id = 'promotion-media'");
    assert.equal(rows[0].public, true);
    assert.equal(Number(rows[0].file_size_limit), 5242880);
    assert.deepEqual(rows[0].allowed_mime_types, ['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
  });
  await check('admin can upload own images and create active/hidden ads', async () => {
    await asRole('authenticated', admin, async (tx) => {
      for (const name of ['active', 'hidden', 'pending']) {
        await tx.query('insert into storage.objects (bucket_id, name, owner_id) values ($1, $2, $3)',
          ['promotion-media', `${admin}/promotions/${name}.webp`, admin]);
      }
      await tx.query(`insert into public.home_promotions
        (id, title, image_url, is_active, sort_order) values
        ($1, 'Active ad', $2, true, 5), ($3, 'Hidden ad', $4, false, 1)`,
        [active, image(admin, 'active'), hidden, image(admin, 'hidden')]);
    });
  });
  await check('anonymous and regular users see only active ads; admin sees both', async () => {
    for (const [role, uid, expected] of [
      ['anon', null, [active]], ['authenticated', member, [active]],
      ['authenticated', admin, [active, hidden]],
    ]) {
      const { rows } = await asRole(role, uid, (tx) => tx.query('select id from public.home_promotions order by id'));
      assert.deepEqual(rows.map((row) => row.id), expected);
    }
  });
  await check('anonymous and regular users cannot create or mutate ads', async () => {
    for (const [role, uid] of [['anon', null], ['authenticated', member]]) {
      await denied(role, uid, 'insert into public.home_promotions (title,image_url) values ($1,$2)',
        ['Forbidden', image(admin, 'active')]);
      if (role === 'anon') {
        await denied(role, uid, 'update public.home_promotions set is_active = false where id = $1', [active]);
        await denied(role, uid, 'delete from public.home_promotions where id = $1', [active]);
      } else {
        for (const sql of [
          'update public.home_promotions set is_active = false where id = $1 returning id',
          'delete from public.home_promotions where id = $1 returning id',
        ]) {
          const { rows } = await asRole(role, uid, (tx) => tx.query(sql, [active]));
          assert.equal(rows.length, 0);
        }
      }
    }
  });
  await check('admin can edit, publish, hide, reorder and delete an ad', async () => {
    await asRole('authenticated', admin, async (tx) => {
      await tx.query('insert into public.home_promotions (id,title,image_url,is_active) values ($1,$2,$3,false)',
        [draft, 'Draft', image(admin, 'active')]);
      const { rows } = await tx.query(`update public.home_promotions set
        title = 'Offer', is_active = true, sort_order = 3, target_url = 'https://example.com/offer'
        where id = $1 returning *`, [draft]);
      assert.equal(rows[0].title, 'Offer');
      assert.equal(rows[0].sort_order, 3);
      assert.equal(rows[0].is_active, true);
      await tx.query('update public.home_promotions set is_active = false where id = $1', [draft]);
      const deleted = await tx.query('delete from public.home_promotions where id = $1 returning id', [draft]);
      assert.equal(deleted.rows.length, 1);
    });
  });
  await check('SQL rejects invalid title, target URL and ordering even for admin', async () => {
    for (const [column, value] of [
      ['title', '   '], ['title', 'x'.repeat(121)], ['sort_order', -1], ['sort_order', 10000],
      ['target_url', 'javascript:alert(1)'], ['target_url', 'https://user:password@example.com'],
    ]) {
      await assert.rejects(() => asRole('authenticated', admin,
        (tx) => tx.query(`update public.home_promotions set ${column} = $1 where id = $2`, [value, active])),
        (error) => error.code === '23514');
    }
  });
  await check('regular users cannot upload despite broad existing storage policy', async () => {
    await denied('authenticated', member,
      'insert into storage.objects (bucket_id,name,owner_id) values ($1,$2,$3)',
      ['promotion-media', `${member}/promotions/forbidden.webp`, member]);
    await denied('anon', null,
      'insert into storage.objects (bucket_id,name) values ($1,$2)',
      ['promotion-media', `${admin}/promotions/anonymous.webp`]);
    await denied('authenticated', admin,
      'insert into storage.objects (bucket_id,name) values ($1,$2)',
      ['promotion-media', `${otherAdmin}/promotions/wrong-owner.webp`]);
  });
  await check('neither admin nor ordinary user can overwrite images', async () => {
    for (const uid of [member, admin]) {
      const { rows } = await asRole('authenticated', uid, (tx) => tx.query(
        "update storage.objects set name = $1 where bucket_id = 'promotion-media' returning id",
        [`${uid}/promotions/replaced.webp`]));
      assert.equal(rows.length, 0);
    }
  });
  await check('referenced active/hidden images and other admin images cannot be deleted', async () => {
    for (const uid of [member, otherAdmin, admin]) {
      const { rows } = await asRole('authenticated', uid, (tx) => tx.query(
        "delete from storage.objects where bucket_id = 'promotion-media' and name = any($1) returning id",
        [[`${admin}/promotions/active.webp`, `${admin}/promotions/hidden.webp`]]));
      assert.equal(rows.length, 0);
    }
    const { rows } = await asRole('authenticated', otherAdmin, (tx) => tx.query(
      "delete from storage.objects where bucket_id = 'promotion-media' and name = $1 returning id",
      [`${admin}/promotions/pending.webp`]));
    assert.equal(rows.length, 0);
  });
  await check('uploader admin can clean an unreferenced pending image', async () => {
    const { rows } = await asRole('authenticated', admin, (tx) => tx.query(
      "delete from storage.objects where bucket_id = 'promotion-media' and name = $1 returning id",
      [`${admin}/promotions/pending.webp`]));
    assert.equal(rows.length, 1);
  });
  await check('other buckets still work and cannot be moved into promotion bucket', async () => {
    await asRole('authenticated', member, async (tx) => {
      await tx.query('insert into storage.objects (bucket_id,name) values ($1,$2)',
        ['control-media', `${member}/media/control.webp`]);
      const updated = await tx.query("update storage.objects set owner_id = $1 where bucket_id = 'control-media' returning id", [member]);
      assert.equal(updated.rows.length, 1);
    });
    await denied('authenticated', member,
      "update storage.objects set bucket_id = 'promotion-media' where bucket_id = 'control-media'");
    const { rows } = await asRole('authenticated', member, (tx) => tx.query(
      "delete from storage.objects where bucket_id = 'control-media' returning id"));
    assert.equal(rows.length, 1);
  });
  console.log(`All ${checks} migration/RLS checks passed in isolated PostgreSQL.`);
} finally {
  await db.close();
}
