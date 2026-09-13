import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {createDeleteAccountHandler} from '../supabase/functions/delete-account/handler.mjs';

function fixture(options = {}) {
  const calls = [];
  let batch = 0;
  const client = {
    auth: {
      getUser: async token => {
        calls.push(['verify', token]);
        return options.invalid ? {error: {message: 'invalid'}} : {data: {user: {id: 'actual-user'}}};
      },
      admin: {deleteUser: async id => { calls.push(['delete', id]); return {error: options.deleteError}; }},
    },
    rpc: async (name, args) => {
      calls.push(['rpc', name, args]);
      if (options.orders) return {error: {message: 'account_has_orders'}};
      if (options.rpcError) return {error: {message: 'unavailable'}};
      return {data: options.media && batch++ === 0 ? [
        {bucket_id: 'images', name: 'actual-user/photo.png'},
        {bucket_id: 'videos', name: 'actual-user/video.mp4'},
      ] : []};
    },
    storage: {from: bucket => ({remove: async paths => {
      calls.push(['remove', bucket, paths]); return {error: options.storageError};
    }})},
  };
  return {calls, handle: createDeleteAccountHandler(client)};
}
function request(body = {confirmation: 'DELETE'}, token = 'valid') {
  return new Request('https://example.test/delete-account', {
    method: 'POST', headers: token ? {Authorization: `Bearer ${token}`} : {}, body: JSON.stringify(body),
  });
}
let f = fixture();
assert.equal((await f.handle(request(undefined, null))).status, 401);
assert.equal(f.calls.length, 0);
f = fixture({invalid: true});
assert.equal((await f.handle(request())).status, 401);
assert.equal(f.calls.length, 1);
f = fixture();
assert.equal((await f.handle(request({}))).status, 400);
assert.equal(f.calls.length, 1);
assert.equal((await f.handle(new Request('https://example.test', {method: 'GET'}))).status, 405);
assert.equal((await f.handle(new Request('https://example.test', {method: 'OPTIONS'}))).status, 204);
console.log('PASS missing/invalid authentication, missing confirmation and GET cannot delete');

f = fixture({media: true});
assert.deepEqual(await (await f.handle(request({confirmation: 'DELETE', user_id: 'victim'}))).json(), {deleted: true});
assert.deepEqual(f.calls.filter(c => c[0] === 'delete'), [['delete', 'actual-user']]);
assert(f.calls.filter(c => c[0] === 'rpc').every(c => c[2].target_user === 'actual-user'));
assert(f.calls.findIndex(c => c[0] === 'remove') < f.calls.findIndex(c => c[0] === 'delete'));
assert.equal(f.calls.filter(c => c[0] === 'remove').length, 2);
console.log('PASS supplied victim ID ignored; only verified owner deleted after Storage API cleanup');

for (const options of [{orders: true}, {rpcError: true}, {media: true, storageError: {}}, {deleteError: {}}]) {
  f = fixture(options);
  const response = await f.handle(request());
  assert.equal(response.status, options.orders ? 409 : 503);
  assert.notEqual((await response.json()).deleted, true);
  if (!options.deleteError) assert(!f.calls.some(c => c[0] === 'delete'));
  if (options.orders) assert(!f.calls.some(c => c[0] === 'remove'));
}
console.log('PASS orders block all deletion; backend failures never report success');

const {PGlite} = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
try {
  const a = '10000000-0000-4000-8000-000000000001';
  const b = '10000000-0000-4000-8000-000000000002';
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema storage;
    create table storage.objects(bucket_id text,name text,owner_id text,owner uuid);
    create table factories(id bigint primary key,owner_id uuid);
    create table orders(buyer_id uuid,factory_id bigint);
    insert into storage.objects values('images','mine','${a}',null),('images','other','${b}',null),('images','legacy',null,'${a}');
    insert into factories values(1,'${a}');`);
  const sql = readFileSync(new URL('../supabase/migrations/20260913230000_account_deletion.sql', import.meta.url), 'utf8');
  await db.exec(sql); await db.exec(sql);
  async function queryAs(role, sql) {
    await db.exec(`begin; set local role ${role}`);
    try { const result = await db.query(sql); await db.exec('commit'); return result; }
    catch (error) { await db.exec('rollback'); throw error; }
  }
  const call = `select * from account_deletion_media('${a}')`;
  for (const role of ['anon', 'authenticated']) {
    await assert.rejects(() => queryAs(role, call), error => error.code === '42501');
  }
  assert.deepEqual((await queryAs('service_role', call)).rows.map(r => r.name), ['legacy', 'mine']);
  for (const values of [`('${a}', null)`, `('${b}', 1)`]) {
    await db.exec('insert into orders values ' + values);
    await assert.rejects(() => queryAs('service_role', call), error => error.message === 'account_has_orders');
    await db.exec('delete from orders');
  }
  console.log('PASS SQL helper service-only, scopes media ownership, blocks buyer/seller orders; repeat migration valid');
} finally { await db.close(); }
