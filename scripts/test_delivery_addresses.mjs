// اختبارات PostgreSQL معزولة: لا تفتح اتصالاً بقاعدة الموقع.
// node scripts/test_delivery_addresses.mjs <temporary-pglite-package-directory>
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

if (!process.argv[2]) throw new Error('Pass the isolated PGlite package directory.');
const { PGlite } = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const alice = '10000000-0000-4000-8000-000000000001';
const bob = '10000000-0000-4000-8000-000000000002';
const first = '20000000-0000-4000-8000-000000000001';
const second = '20000000-0000-4000-8000-000000000002';
const address = (id = first, extra = {}) => ({
  id, label: '  Home  ', address_line: '  Riyadh, King Fahd road  ',
  latitude: 24.7, longitude: 46.7, floor: '  2 ', apartment: '10', ...extra,
});
let checks = 0;

async function check(name, action) {
  await action();
  checks++;
  console.log(`PASS ${name}`);
}

async function asUser(uid, action, role = 'authenticated') {
  assert(['anon', 'authenticated'].includes(role));
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    const result = await action(db);
    await db.exec('commit');
    return result;
  } catch (error) {
    await db.exec('rollback');
    throw error;
  }
}

const save = (uid, value, expected = uid) => asUser(uid, (tx) => tx.query(
  'select * from public.save_delivery_address($1::uuid, $2::jsonb)', [expected, JSON.stringify(value)],
));
const select = (uid, id, expected = uid) => asUser(uid, (tx) => tx.query(
  'select * from public.select_delivery_address($1::uuid, $2::uuid)', [expected, id],
));
const remove = (uid, id, expected = uid) => asUser(uid, (tx) => tx.query(
  'select * from public.delete_delivery_address($1::uuid, $2::uuid)', [expected, id],
));
const list = (uid) => asUser(uid, (tx) => tx.query('select * from public.delivery_addresses order by id'));
const rejected = (action, code) => assert.rejects(action, (error) => error.code === code);

try {
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    grant usage on schema auth, public to anon, authenticated;
    create table auth.users (id uuid primary key);
    insert into auth.users values ('${alice}'), ('${bob}');
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  `);
  const migration = await readFile(new URL(
    '../supabase/migrations/20260910060000_delivery_addresses.sql', import.meta.url,
  ), 'utf8');
  await check('migration is rerunnable', async () => {
    await db.exec(migration);
    await db.exec(migration);
  });
  await check('save trims details and selects the saved address atomically', async () => {
    const { rows } = await save(alice, address());
    assert.equal(rows.length, 1);
    assert.equal(rows[0].label, 'Home');
    assert.equal(rows[0].floor, '2');
    assert.equal(rows[0].user_id, alice);
    assert.equal(rows[0].is_default, true);
    const next = await save(alice, address(second, { label: 'Office' }));
    assert.equal(next.rows.length, 2);
    assert.deepEqual(next.rows.filter((row) => row.is_default).map((row) => row.id), [second]);
  });
  await check('reads are private even when a broad policy is added', async () => {
    await db.exec(`create policy deliberately_broad_read on public.delivery_addresses
      for select to authenticated using (true)`);
    assert.equal((await list(bob)).rows.length, 0);
    assert.equal((await list(alice)).rows.length, 2);
  });
  await check('anonymous users cannot read addresses or invoke mutation RPCs', async () => {
    for (const sql of [
      'select * from public.delivery_addresses',
      `select * from public.save_delivery_address('${alice}', '{}'::jsonb)`,
      `select * from public.select_delivery_address('${alice}', '${first}')`,
      `select * from public.delete_delivery_address('${alice}', '${first}')`,
    ]) await rejected(() => asUser(null, (tx) => tx.query(sql), 'anon'), '42501');
  });
  await check('direct writes cannot bypass selection, ownership or address limits', async () => {
    for (const uid of [alice, bob]) {
      for (const sql of [
        'delete from public.delivery_addresses',
        'update public.delivery_addresses set is_default = false',
        `insert into public.delivery_addresses (id,user_id,label,address_line,latitude,longitude)
          values ('${first}', '${uid}', 'Fake', 'Fake', 1, 1)`,
      ]) await rejected(() => asUser(uid, (tx) => tx.query(sql)), '42501');
    }
  });
  await check('RPCs reject expired account context and missing authentication', async () => {
    for (const action of [
      () => save(bob, address(), alice),
      () => select(bob, first, alice),
      () => remove(bob, first, alice),
      () => save(null, address(), alice),
    ]) await rejected(action, '42501');
  });
  await check('another account cannot select or delete an address by UUID', async () => {
    await rejected(() => select(bob, first), '22023');
    await rejected(() => remove(bob, first), '22023');
    // المعرف مركب مع user_id؛ حتى إعادة استخدام UUID لا تعدل بيانات صاحبه.
    await save(bob, address(first, { label: 'Bob only', user_id: alice }));
    assert.equal((await list(alice)).rows.find((row) => row.id === first).label, 'Home');
    const bobRows = (await list(bob)).rows;
    assert.equal(bobRows.length, 1);
    assert.equal(bobRows[0].user_id, bob);
  });
  await check('selection is persisted and exactly one address stays selected', async () => {
    const { rows } = await select(alice, first);
    assert.deepEqual(rows.filter((row) => row.is_default).map((row) => row.id), [first]);
    assert.deepEqual((await list(alice)).rows.filter((row) => row.is_default).map((row) => row.id), [first]);
  });
  await check('invalid coordinates and fields fail without losing prior selection', async () => {
    for (const extra of [
      { latitude: 91 }, { longitude: -181 }, { latitude: 'NaN' }, { longitude: 'Infinity' },
      { label: '' }, { label: 'x'.repeat(61) }, { address_line: ' ' }, { floor: 'x'.repeat(41) },
    ]) await rejected(() => save(alice, address(second, extra)), '22023');
    assert.deepEqual((await list(alice)).rows.filter((row) => row.is_default).map((row) => row.id), [first]);
  });
  await check('deleting selected address selects the remaining address', async () => {
    const { rows } = await remove(alice, first);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].id, second);
    assert.equal(rows[0].is_default, true);
    assert.equal((await remove(alice, second)).rows.length, 0);
  });
  await check('maximum is 20 addresses per account; editing is still allowed', async () => {
    for (let i = 1; i <= 20; i++) {
      await save(alice, address(`30000000-0000-4000-8000-${String(i).padStart(12, '0')}`));
    }
    await rejected(() => save(alice, address()), '22023');
    const rows = (await save(alice, address('30000000-0000-4000-8000-000000000001', {
      label: 'Updated',
    }))).rows;
    assert.equal(rows.length, 20);
    assert.equal(rows.filter((row) => row.is_default).length, 1);
    assert.equal((await list(bob)).rows.length, 1);
  });
  await check('account deletion removes its saved addresses', async () => {
    await db.query('delete from auth.users where id = $1', [alice]);
    assert.equal((await db.query('select * from public.delivery_addresses where user_id = $1', [alice])).rows.length, 0);
  });
  console.log(`${checks} delivery-address checks passed.`);
} finally {
  await db.close();
}
