// اختبار صلاحية مساعد الأسعار وإنشاء الطلب ببيانات وهمية في قاعدة معزولة.
// node scripts/test_tier_price_permissions.mjs <pglite-directory> [diagnostic-json]
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite}=createRequire(resolve(process.argv[2],'package.json'))('@electric-sql/pglite');
const db=new PGlite();
const buyer='30000000-0000-4000-8000-000000000001';
const other='30000000-0000-4000-8000-000000000002';
const defs=new Map();
for(const file of ['20260907130000_price_tiers.sql','20260908160000_fix_tier_price_numeric.sql']){
  const sql=await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8');
  for(const m of sql.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\([\s\S]*?\bas\s+(\$[a-zA-Z0-9_]*\$)[\s\S]*?\2\s*;/gi)) defs.set(m[1],m[0]);
}
if(process.argv[3]) for(const row of JSON.parse(await readFile(resolve(process.argv[3]),'utf8'))){
  if(row.object_type==='function') defs.set(row.object_name.split('(')[0].replace(/^public\./,''),row.definition);
}
const fix=await readFile(new URL('../supabase/migrations/20260912160000_restrict_tier_price_helper.sql',import.meta.url),'utf8');
let checks=0;
async function check(name,fn){await fn();console.log('PASS '+name);checks++;}
async function client(role,uid,sql){
  assert(['anon','authenticated'].includes(role));
  await db.exec('begin');
  try{
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[uid??'']);
    const result=await db.query(sql);await db.exec('commit');return result.rows;
  }catch(e){await db.exec('rollback');throw e;}
}
try{
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema public,auth to anon,authenticated;
    create table products(id bigint primary key,factory_id bigint,name text,price numeric,tiers jsonb,visible boolean);
    create table carts(id bigint primary key,owner_id uuid);
    create table cart_items(cart_id bigint,product_id bigint,quantity numeric);
    create table custom_prices(product_id bigint,customer_id uuid,price numeric);
    create table orders(id uuid primary key default gen_random_uuid(),buyer_id uuid,factory_id bigint,status text,
      subtotal numeric,shipping numeric,payment_fee numeric,vat_rate numeric,vat_amount numeric,total numeric,
      idempotency_key uuid,updated_at timestamptz default now(),unique(buyer_id,idempotency_key));
    create table order_items(order_id uuid,product_id bigint,product_name text,unit_price numeric,quantity numeric,line_total numeric);
    insert into products values
      (1,1,'Tiered',10,'[{"min":1,"max":9,"price":10},{"min":10,"price":8}]',true),
      (2,2,'Hidden',999,'[]',false), (3,1,'Base price',5,'[]',true);
    insert into carts values(1,'${buyer}'),(2,'${other}');
    alter table products enable row level security;
    create policy visible_products on products for select using(visible);
    grant select on products to anon,authenticated;
  `);
  await db.exec(defs.get('tier_unit_price'));
  await db.exec(defs.get('create_order_from_cart'));
  await db.exec('revoke execute on function public.create_order_from_cart(bigint,uuid) from public,anon; grant execute on function public.create_order_from_cart(bigint,uuid) to authenticated;');
  await check('reproduce hidden price disclosure without direct product access',async()=>{
    for(const [role,uid] of [['anon',null],['authenticated',buyer]]){
      assert.equal((await client(role,uid,'select * from products where id=2')).length,0);
      assert.equal(Number((await client(role,uid,'select tier_unit_price(2,1) as price'))[0].price),999);
    }
  });
  const before=(await db.query("select oid,prosrc from pg_proc where proname in ('tier_unit_price','create_order_from_cart') order by oid")).rows;
  await check('migration is repeatable and preserves pricing and checkout bodies',async()=>{
    await db.exec(fix);await db.exec(fix);
    assert.deepEqual((await db.query("select oid,prosrc from pg_proc where proname in ('tier_unit_price','create_order_from_cart') order by oid")).rows,before);
  });
  await check('visitors and signed-in users cannot call the price helper directly',async()=>{
    for(const [role,uid] of [['anon',null],['authenticated',buyer]])
      await assert.rejects(()=>client(role,uid,'select tier_unit_price(2,1)'),e=>e.code==='42501');
  });
  await check('checkout preserves tier price, fractional quantity, base price and custom price',async()=>{
    for(const [product,quantity,unit,custom] of [[1,10,8,null],[1,9.5,10,null],[3,2,5,null],[1,10,6,6]]){
      await db.exec(`delete from custom_prices; insert into cart_items values(1,${product},${quantity});`);
      if(custom!==null) await db.exec(`insert into custom_prices values(1,'${buyer}',${custom});`);
      const [order]=await client('authenticated',buyer,'select * from create_order_from_cart(1)');
      const subtotal=quantity*unit;
      assert.equal(Number(order.subtotal),subtotal);
      const fee=Math.round((subtotal+30)*0.01*100)/100;
      const vat=Math.round((subtotal+30+fee)*0.15*100)/100;
      assert.equal(Number(order.total),subtotal+30+fee+vat);
      const [item]=(await db.query('select * from order_items where order_id=$1',[order.id])).rows;
      assert.equal(Number(item.unit_price),unit);assert.equal(Number(item.line_total),subtotal);
      assert.equal((await db.query('select * from cart_items where cart_id=1')).rows.length,0);
    }
  });
  await check('checkout still requires login and cannot consume another buyer cart',async()=>{
    await db.exec('insert into cart_items values(1,1,10)');
    await assert.rejects(()=>client('anon',null,'select * from create_order_from_cart(1)'),e=>e.code==='42501');
    await assert.rejects(()=>client('authenticated',null,'select * from create_order_from_cart(1)'),e=>e.code==='42501');
    await assert.rejects(()=>client('authenticated',other,'select * from create_order_from_cart(1)'),e=>e.code==='22023');
    assert.equal((await db.query('select * from cart_items where cart_id=1')).rows.length,1);
  });
  await check('unexpected policy dependency aborts without revoking access',async()=>{
    await db.exec('grant execute on function tier_unit_price(bigint,numeric) to anon; create policy unexpected on products for select using(tier_unit_price(id,1)>0);');
    await assert.rejects(()=>db.exec(fix),/Review policy dependencies/);await db.exec('rollback');
    assert.equal((await db.query("select has_function_privilege('anon','tier_unit_price(bigint,numeric)','EXECUTE') as allowed")).rows[0].allowed,true);
    await db.exec('drop policy unexpected on products;');await db.exec(fix);
  });
  await check('checkout owner mismatch aborts the migration',async()=>{
    await db.exec('create role different_owner; alter function create_order_from_cart(bigint,uuid) owner to different_owner;');
    await assert.rejects(()=>db.exec(fix),/Checkout must execute/);await db.exec('rollback');
  });
  console.log(`Completed ${checks} checks. No production data accessed.`);
}finally{await db.close();}
