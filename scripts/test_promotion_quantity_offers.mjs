import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite}=createRequire(resolve(process.argv[2], 'package.json'))('@electric-sql/pglite');
const db=new PGlite();
const migration=readFileSync(new URL('../supabase/migrations/20260923100000_promotion_quantity_offers.sql',import.meta.url),'utf8');
const promo='10000000-0000-4000-8000-000000000001';
const hidden='10000000-0000-4000-8000-000000000002';
let checks=0;
async function check(name,fn){await fn();checks++;console.log('PASS '+name);}
async function offers(offset=0,limit=20,id=promo){
 return (await db.query('select public.get_promotion_quantity_offers($1,$2,$3) as result',[id,offset,limit])).rows[0].result;
}
async function product(id,tiers,factory=1,moq=1,price=100){
 await db.query('insert into public.products(id,factory_id,name,price,moq,tiers) values($1,$2,$3,$4,$5,$6)',[id,factory,'Product '+id,price,moq,JSON.stringify(tiers)]);
}
try{
 await db.exec(`
 create role anon; create role authenticated;
 create table public.home_promotions(id uuid primary key,image_url text,target_url text default '',is_active boolean default true);
 create table public.factories(id bigint primary key,name text,industry text,status text);
 create table public.products(id bigint primary key,factory_id bigint,name text,image text,images jsonb default '[]',price numeric,moq integer,tiers jsonb);
 alter table public.home_promotions enable row level security;
 create policy active_ads on public.home_promotions for select using(is_active);
 alter table public.products enable row level security;
 create policy public_products on public.products for select using(exists(select 1 from public.factories f where f.id=factory_id and f.status='approved'));
 grant usage on schema public to anon,authenticated;
 grant select on public.home_promotions,public.factories,public.products to anon,authenticated;
 insert into public.factories values(1,'Approved','Food & Beverages','approved'),(2,'Other category','Toys','approved'),(3,'Pending','Food & Beverages','pending');
 insert into public.home_promotions(id) values('${promo}');
 insert into public.home_promotions(id,is_active) values('${hidden}',false);
 `);
 await check('migration is repeatable',async()=>{await db.exec(migration);await db.exec(migration);});
 await check('existing artwork is mapped and configured destinations survive reapplication',async()=>{
  const seedId='047bbbde-e143-42cf-9505-2ef744d470b7';
  await db.query('insert into public.home_promotions(id,image_url) values($1,$2)',[seedId,'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/c6d14284-7a8b-45bb-a5f4-4b96c7eb4dad.png']);
  await db.exec(migration);
  let seeded=(await db.query('select * from public.home_promotions where id=$1',[seedId])).rows[0];
  assert.equal(seeded.discount_category,'Electronics & Electrical Appliances');assert.equal(Number(seeded.discount_percent),25);
  await db.query('update public.home_promotions set discount_percent=30 where id=$1',[seedId]);
  await db.exec(migration);
  seeded=(await db.query('select * from public.home_promotions where id=$1',[seedId])).rows[0];assert.equal(Number(seeded.discount_percent),30);
  await db.query('delete from public.home_promotions where id=$1',[seedId]);
 });
 await db.query('update public.home_promotions set discount_category=$1,discount_percent=40',['Food & Beverages']);
 await product(1,[{min:1,max:49,price:25},{min:50,max:null,price:15}]);
 await product(2,[{min:1,max:9,price:100},{min:10,max:99,price:70},{min:100,price:60}]);
 await product(3,[{min:1,max:9,price:100},{min:10,price:62}]);
 await product(4,[{min:1,max:9,price:100},{min:10,price:20}],2);
 await product(5,[{min:1,max:9,price:100},{min:10,price:20}],3);
 await product(6,[]);
 await product(7,[{min:1,price:50}]);
 await product(8,[{min:1,max:9,price:50},{min:10,price:50}]);
 await product(9,[{min:'bad',price:'bad'},{min:'9999999999999999999999999',price:0},{min:1,max:-1,price:10}]);
 await product(10,[{min:1,max:9,price:100},{min:10,price:50}],1,15);
 await check('exact then nearest discount, one result per product',async()=>{
  const p=await offers();assert.deepEqual(p.items.map(p=>p.id),[1,2,3]);
  assert.equal(p.items[0].discount_percent,40);assert.equal(p.items[0].unit_price,15);
  assert.equal(p.items[0].min_quantity,50);assert.equal(p.items[0].max_quantity,null);
  assert.equal(p.items[0].reference_price,25);assert.equal(p.items[0].reference_max,49);
 });
 await check('best matching tier instead of always the cheapest tier',async()=>{
  await db.exec('update public.home_promotions set discount_percent=30');
  const p=await offers();assert.equal(p.items[0].id,2);assert.equal(p.items[0].unit_price,70);assert.equal(p.items[0].max_quantity,99);
  await db.exec('update public.home_promotions set discount_percent=40');
 });
 await check('paginated results are stable and complete',async()=>{
  const first=await offers(0,2),second=await offers(2,2);
  assert.equal(first.has_more,true);assert.equal(second.has_more,false);
  assert.deepEqual([...first.items,...second.items].map(p=>p.id),[1,2,3]);
 });
 await check('hidden and deleted banners are unavailable, even for owner',async()=>{
  assert.equal(await offers(0,20,hidden),null);
  assert.equal(await offers(0,20,'00000000-0000-0000-0000-000000000000'),null);
 });
 await check('overlapping ranges show only the effective quantity interval',async()=>{
  await product(11,[{min:1,price:100},{min:10,price:60},{min:20,max:29,price:80}]);
  const row=(await offers()).items.find(p=>p.id===11);
  assert.equal(row.unit_price,60);assert.equal(row.min_quantity,10);assert.equal(row.max_quantity,19);
 });
 await check('ambiguous duplicate thresholds cannot advertise a fictional price',async()=>{
  await product(12,[{min:1,max:9,price:100},{min:10,price:60},{min:10,price:20}]);
  assert(!(await offers()).items.some(p=>p.id===12));
 });
 await check('live tier edits immediately change the offer',async()=>{
  await db.query('update public.products set tiers=$1 where id=1',[JSON.stringify([{min:1,max:49,price:25},{min:50,price:10}])]);
  assert.equal((await offers()).items.find(p=>p.id===1).discount_percent,60);
 });
 await check('empty categories return an honest empty result',async()=>{
  await db.exec("update public.home_promotions set discount_category='Cleaning Products & Detergents'");
  assert.deepEqual((await offers()).items,[]);
  await db.exec("update public.home_promotions set discount_category='Food & Beverages'");
 });
 await check('metadata requires a complete pair and excludes conflicting links',async()=>{
  await assert.rejects(db.exec(`update public.home_promotions set discount_percent=null where id='${promo}'`));
  await assert.rejects(db.exec(`update public.home_promotions set discount_percent=100 where id='${promo}'`));
  await assert.rejects(db.exec(`update public.home_promotions set target_url='https://example.com' where id='${promo}'`));
 });
 await check('anonymous visitors can read public offers but cannot change banners',async()=>{
  await db.exec('set role anon');
  assert((await offers()).items.length>0);assert.equal(await offers(0,20,hidden),null);
  await assert.rejects(db.exec(`update public.home_promotions set discount_percent=1 where id='${promo}'`));
  await db.exec('reset role');
 });
 console.log(`${checks} quantity-offer SQL checks passed`);
}finally{await db.close();}
