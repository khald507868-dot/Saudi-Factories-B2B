// اختبارات PostgreSQL في الذاكرة فقط؛ لا اتصال بالإنتاج ولا حذف ملفات.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite} = createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db = new PGlite();
const read = f => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
const uid = n => `70000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
let serial = 100;
async function as(n, sql, args = [], role = 'authenticated') {
  await db.exec('begin; set local role ' + role);
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)", [n ? uid(n) : '', role]);
    const r = await db.query(sql, args); await db.exec('commit'); return r.rows;
  } catch (e) { await db.exec('rollback'); throw e; }
}
const buy = (factory = 1, key = uid(++serial), user = 1) => as(user, 'select * from create_order_from_cart($1,$2)', [factory, key]);
async function cart(product = 1, quantity = 10) {
  await db.exec('delete from cart_items where cart_id=1');
  await db.query('insert into cart_items(cart_id,product_id,quantity) values(1,$1,$2)', [product, quantity]);
}
let checks = 0;
async function check(name, fn) { await fn(); checks++; console.log('PASS ' + name); }
try {
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth; create schema storage; create table storage.objects(id int);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin boolean default false);
    create table factories(id bigint primary key,owner_id uuid,status text);
    create table products(id bigint primary key,factory_id bigint references factories(id),name text,price numeric,tiers jsonb);
    create table custom_prices(product_id bigint,factory_id bigint,customer_id uuid,price numeric);
    grant usage on schema public,auth to anon,authenticated;
  `);
  const schema = read('schema.sql');
  for (const table of ['carts','cart_items','orders','order_items']) {
    await db.exec(schema.match(new RegExp('create table if not exists public\\.' + table + ' \\([\\s\\S]*?\\n\\);'))[0]);
  }
  await db.exec('alter table orders add shipping numeric(14,2),add payment_fee numeric(14,2),add vat_rate numeric(5,4),add vat_amount numeric(14,2)');
  for (let n = 1; n <= 4; n++) {
    await db.query('insert into auth.users values($1,$2)', [uid(n), n === 4 ? null : '2026-09-17']);
    await db.query("insert into profiles values($1,'individual',false)", [uid(n)]);
    await db.query('insert into carts(owner_id) values($1)', [uid(n)]);
  }
  await db.query("insert into factories values(1,$1,'approved'),(2,$1,'rejected')", [uid(3)]);
  await db.exec(`insert into products values
    (1,1,'Tiered',10,'[{"min":1,"max":9,"price":10},{"min":10,"price":8}]'),
    (2,2,'Hidden',999,'[]'),(3,1,'Base',5,'[]');
    alter table products enable row level security;
    create policy visible_products on products for select using(factory_id=1);
    grant select on products to anon,authenticated;
  `);
  await db.exec(read('supabase/migrations/20260908160000_fix_tier_price_numeric.sql'));
  const historical = read('supabase/migrations/20260907130000_price_tiers.sql').match(/create or replace function public.create_order_from_cart\([\s\S]*?\$fn\$;/)[0];
  await db.exec(historical);
  await db.exec(read('supabase/migrations/20260913210000_account_approval_gate.sql'));
  await check('reproduce checkout of an invisible rejected factory with the previous function', async () => {
    assert.equal((await as(1, 'select * from products where id=2')).length, 0);
    await cart(2, 1);
    assert.equal((await buy(2))[0].factory_id, 2);
  });
  await check('reproduce adding new items to an already paid order using its old request key', async () => {
    await cart(); const key = uid(++serial); const [order] = await buy(1, key);
    await db.query("update orders set status='paid' where id=$1", [order.id]);
    await cart(3, 100); const [replayed] = await buy(1, key);
    assert.equal(replayed.status, 'paid'); assert.equal(replayed.total, order.total);
    assert.equal((await db.query('select count(*)::int n from order_items where order_id=$1', [order.id])).rows[0].n, 2);
  });
  const fix = read('supabase/migrations/20260917100000_checkout_security.sql');
  await check('migration can run twice and the internal price helper stays private', async () => {
    await db.exec(fix); await db.exec(fix);
    await db.exec('revoke execute on function tier_unit_price(bigint,numeric) from public,anon,authenticated');
    await assert.rejects(() => as(1, 'select tier_unit_price(1,10)'), e => e.code === '42501');
  });
  await check('rejected and nonexistent factories fail without consuming the cart', async () => {
    await cart(2, 1);
    await assert.rejects(() => buy(2), /Factory unavailable/);
    await assert.rejects(() => buy(999), /Factory unavailable/);
    assert.equal((await db.query('select * from cart_items where cart_id=1')).rows.length, 1);
  });
  await check('paid-order retries preserve all order fields/items and leave newly added cart items', async () => {
    await cart(); const key = uid(++serial); const [order] = await buy(1, key);
    await db.query("update orders set status='paid' where id=$1", [order.id]);
    const before = (await db.query('select * from orders where id=$1', [order.id])).rows[0];
    const itemsBefore = (await db.query('select * from order_items where order_id=$1', [order.id])).rows;
    assert.deepEqual((await buy(1, key))[0], before);
    await cart(3, 100);
    assert.deepEqual((await buy(1, key))[0], before);
    assert.deepEqual((await db.query('select * from order_items where order_id=$1', [order.id])).rows, itemsBefore);
    assert.equal((await db.query('select quantity from cart_items where cart_id=1')).rows[0].quantity, '100.000');
    await assert.rejects(() => buy(2, key), /another factory/);
  });
  await check('tier, fractional, base and negotiated prices retain correct totals', async () => {
    for (const [product, quantity, unit, custom] of [[1,10,8,null],[1,9.5,10,null],[3,2,5,null],[1,10,6,6]]) {
      await db.exec('delete from custom_prices');
      if (custom !== null) await db.query('insert into custom_prices values(1,1,$1,$2)', [uid(1), custom]);
      await cart(product, quantity); const [order] = await buy();
      const subtotal = quantity * unit;
      const fee = Math.round((subtotal + 30) * 100 * 0.01) / 100;
      const vat = Math.round((subtotal + 30 + fee) * 100 * 0.15) / 100;
      assert.equal(Number(order.subtotal), subtotal); assert.equal(Number(order.total), subtotal + 30 + fee + vat);
      const [item] = (await db.query('select * from order_items where order_id=$1', [order.id])).rows;
      assert.equal(Number(item.unit_price), unit); assert.equal(Number(item.line_total), subtotal);
    }
    await db.exec('delete from custom_prices');
  });
  await check('invalid prices/quantities and mixed factories fail atomically', async () => {
    for (const value of [null, '-1', 'NaN', 'Infinity', '1000000000000']) {
      await db.query('update products set price=$1 where id=3', [value]); await cart(3, 1);
      await assert.rejects(() => buy(), /unpriced products/);
    }
    await db.exec('update products set price=5 where id=3');
    await cart(1, 'NaN'); await assert.rejects(() => buy(), /unpriced products/);
    await cart(); await db.exec('insert into cart_items(cart_id,product_id,quantity) values(1,2,1)');
    await assert.rejects(() => buy(), /one order per factory/);
    await cart(); await assert.rejects(() => buy(1, null), /request key/);
  });
  await check('login, email approval and other-buyer isolation remain enforced', async () => {
    await cart();
    await assert.rejects(() => as(0, 'select * from create_order_from_cart(1)', [], 'anon'), e => e.code === '42501');
    await assert.rejects(() => buy(1, uid(++serial), 0), e => e.code === '42501');
    await assert.rejects(() => buy(1, uid(++serial), 2), /no products/);
    await db.exec('insert into cart_items(cart_id,product_id,quantity) values(4,1,10)');
    await assert.rejects(() => buy(1, uid(++serial), 4), e => e.code === '42501');
    assert.equal((await db.query('select * from cart_items where cart_id=4')).rows.length, 1);
  });
  await check('order items use the captured prices and later cart additions survive', async () => {
    // محاكاة تغيير بين إنشاء رأس الطلب وإدراج أصنافه، داخل المعاملة نفسها.
    await db.exec(`create function checkout_test_interleave() returns trigger language plpgsql as $$
      begin
        update public.products set tiers='[]',price=300 where id=1;
        insert into public.cart_items(cart_id,product_id,quantity) values(1,3,2);
        return new;
      end $$;
      create trigger checkout_test_interleave after insert on orders
      for each row execute function checkout_test_interleave();`);
    await cart(); const [order] = await buy();
    const items = (await db.query('select * from order_items where order_id=$1', [order.id])).rows;
    assert.equal(items.length, 1); assert.equal(items[0].unit_price, '8.00');
    assert.equal(items[0].line_total, order.subtotal);
    const remaining = (await db.query('select product_id from cart_items where cart_id=1')).rows;
    assert.deepEqual(remaining, [{product_id: 3}]);
    await db.exec('drop trigger checkout_test_interleave on orders; drop function checkout_test_interleave()');
  });
  console.log(`Completed ${checks} checkout security checks; no production access.`);
} finally { await db.close(); }
