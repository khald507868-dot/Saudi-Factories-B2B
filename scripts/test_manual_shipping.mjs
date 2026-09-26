// قاعدة PostgreSQL معزولة؛ لا طلبات حقيقية ولا اتصال ببيانات الإنتاج.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const {PGlite}=createRequire(resolve(process.argv[2],'package.json'))('@electric-sql/pglite');
const db=new PGlite();
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const uid=n=>`90000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
let checks=0,serial=100;
async function as(n,sql,args=[],role='authenticated') {
  await db.exec('begin; set local role '+role);
  try {await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[n?uid(n):'',role]);const r=await db.query(sql,args);await db.exec('commit');return r.rows;}
  catch(e){await db.exec('rollback');throw e;}
}
const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
const check=async(name,fn)=>{await fn();checks++;console.log('PASS '+name);};
const order=async()=>{await db.exec('insert into cart_items(cart_id,product_id,quantity) values(1,1,10)');return (await as(2,'select * from create_order_from_cart(1,$1)',[uid(++serial)]))[0];};
const shipment=id=>one('select * from order_shipments where order_id=$1',[id]);
const future=days=>new Date(Date.now()+days*86400000).toISOString();
const destination={country:'UAE',city:'Dubai',address:'Warehouse 12',contact:'Buyer',phone:'+9711234567',postal_code:''};
const packing={pickup_address:'Jeddah, warehouse 2',contact:'Factory',phone:'+9661234567',refrigerated:false,special_requirements:'None',packages:[{type:'pallet',count:2,length_cm:120,width_cm:80,height_cm:150,weight_kg:250}]};
const quote=()=>({carrier:'Manual carrier',carrier_quote_reference:'OFFER-22',freight:100,additional_fees:20,taxes:5,estimated_days_min:3,estimated_days_max:7,expires_at:future(3),inclusions:'Pickup and port delivery',exclusions:'Buyer pays import duty'});
async function action(user,id,act,data={},revision){const s=await shipment(id);return(await as(user,'select * from update_manual_shipping($1,$2,$3)',[id,act,{revision:revision??s.revision,...data}]))[0];}
async function prepare(id){await action(2,id,'destination',{destination,delivery_type:'door'});await action(1,id,'packing',{packing,ready_at:future(1)});return action(6,id,'quote',quote());}
try {
  await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema storage;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
    create table auth.users(id uuid primary key,email_confirmed_at timestamptz);
    create table profiles(id uuid primary key,account_type text,is_admin boolean default false);
    create table factories(id bigint primary key,owner_id uuid references profiles(id),status text,name text);
    create table products(id bigint primary key,factory_id bigint references factories(id),name text,price numeric,tiers jsonb,images text[],image text);
    create table custom_prices(product_id bigint,factory_id bigint,customer_id uuid,price numeric);
    create table conversations(id bigint primary key,factory_id bigint references factories(id),individual_id uuid references profiles(id));
    create table messages(id bigint generated always as identity primary key,conversation_id bigint references conversations(id),sender_id uuid references profiles(id),body text);
    create table storage.objects(id int);
    create function is_admin() returns boolean language sql stable security definer set search_path='' as $$select coalesce((select is_admin from public.profiles where id=auth.uid()),false)$$;
    grant usage on schema public,auth to anon,authenticated;
  `);
  for(const table of ['carts','cart_items','orders','order_items']) await db.exec(read('schema.sql').match(new RegExp('create table if not exists public\\.'+table+' \\([\\s\\S]*?\\n\\);'))[0]);
  await db.exec('alter table orders add shipping numeric(14,2),add payment_fee numeric(14,2),add vat_rate numeric(5,4),add vat_amount numeric(14,2)');
  for(let n=1;n<=6;n++){
    await db.query('insert into auth.users values($1,$2)',[uid(n),n===5?null:'2026-09-18']);
    await db.query('insert into profiles values($1,$2,$3)',[uid(n),[1,3].includes(n)?'factory':'individual',n===6]);
  }
  await db.query("insert into factories values(1,$1,'approved','Jeddah'),(2,$2,'approved','Riyadh')",[uid(1),uid(3)]);
  await db.query('insert into carts(owner_id) values($1)',[uid(2)]);
  await db.query('insert into conversations values(1,1,$1)',[uid(2)]);
  await db.exec("insert into products values(1,1,'Product',10,'[]','{}',''),(2,2,'Second factory',20,'[]','{}','')");
  await db.exec(read('supabase/migrations/20260908160000_fix_tier_price_numeric.sql'));
  await db.exec(read('supabase/migrations/20260913210000_account_approval_gate.sql'));
  await db.exec(read('supabase/migrations/20260914120000_private_chat_offers.sql'));
  await db.exec(read('supabase/migrations/20260906120000_mark_order_paid.sql'));
  const [legacyOffer]=await as(1,"select * from create_private_chat_offer(1,1,10,12,7,'',$1)",[uid(++serial)]);
  const [acceptedLegacy]=await as(2,'select * from accept_private_chat_offer($1)',[legacyOffer.id]);
  const legacy=await one('select * from orders where id=$1',[acceptedLegacy.order_id]);
  const [oldPending]=await as(1,"select * from create_private_chat_offer(1,1,10,12,7,'',$1)",[uid(++serial)]);
  const migration=read('supabase/migrations/20260918100000_manual_shipping.sql');
  await check('migration reruns without repricing historical orders or offers',async()=>{
    await db.exec(migration);await db.exec(migration);
    const verification=await db.query(read('supabase/diagnostics/manual_shipping_check.sql'));
    assert.equal(verification.rows.length,7);
    assert(verification.rows.every(r=>r.passed),JSON.stringify(verification.rows));
    assert.deepEqual(await one('select * from orders where id=$1',[legacy.id]),{...legacy,shipping_pricing:'legacy'});
    await assert.rejects(()=>as(2,'select * from accept_private_chat_offer($1)',[oldPending.id]),/offer_shipping_reissue_required/);
    assert.equal((await as(2,'select * from accept_private_chat_offer($1)',[legacyOffer.id]))[0].order_id,legacy.id);
  });
  let id;
  await check('separate factory orders, no fixed shipping, retries preserve snapshots',async()=>{
    await db.exec('insert into cart_items(cart_id,product_id,quantity) values(1,1,10),(1,2,2)');
    const key=uid(++serial),[o]=await as(2,'select * from create_order_from_cart(1,$1)',[key]);id=o.id;
    assert.equal(o.shipping,'0.00');assert.equal(o.total,'116.15');assert.equal(o.status,'awaiting_shipping');
    assert.equal((await one('select count(*)::int n from cart_items')).n,1);
    assert.equal((await as(2,'select * from create_order_from_cart(1,$1)',[key]))[0].id,id);
    const [second]=await as(2,'select * from create_order_from_cart(2,$1)',[uid(++serial)]);
    assert.notEqual(second.id,id);assert.equal(second.factory_id,2);
    assert.equal((await one('select count(*)::int n from order_shipments')).n,2);
    await assert.rejects(()=>as(1,'select * from mark_order_paid($1)',[id]),/not awaiting payment/);
  });
  await check('only parties can read; only RPCs write; admin sees requests',async()=>{
    await assert.rejects(()=>as(0,"select * from update_manual_shipping($1,'quote','{}')",[id],'anon'),e=>e.code==='42501');
    await assert.rejects(()=>as(0,"select * from update_manual_shipping($1,'quote','{}')",[id]),e=>e.code==='42501');
    for(const table of ['order_shipments','shipping_quotes','shipping_events']){
      assert.equal((await as(4,'select * from '+table)).length,0);
      await assert.rejects(()=>as(2,'delete from '+table),e=>e.code==='42501');
      await assert.rejects(()=>as(2,'select * from '+table,[],'anon'),e=>e.code==='42501');
    }
    assert.equal((await as(1,'select * from order_shipments')).length,1);
    assert.equal((await as(6,'select * from order_shipments')).length,2);
    await assert.rejects(()=>action(4,id,'destination',{destination,delivery_type:'door'}),/access_denied/);
    await assert.rejects(()=>action(5,id,'destination',{destination,delivery_type:'door'}),/access_denied/);
    await assert.rejects(()=>action(1,id,'destination',{destination,delivery_type:'door'}),/access_denied/);
    await assert.rejects(()=>action(2,id,'packing',{packing,ready_at:future(1)}),/access_denied/);
    await assert.rejects(()=>action(1,id,'quote',quote()),/access_denied/);
    await assert.rejects(()=>as(2,"select shipping_text('{}','name',20)"),e=>e.code==='42501');
  });
  await check('destination and packing validation; both required before quoting',async()=>{
    await assert.rejects(()=>action(6,id,'quote',quote()),/locked/);
    await assert.rejects(()=>action(2,id,'destination',{destination:{...destination,country:''},delivery_type:'door'}),/invalid/);
    await assert.rejects(()=>action(2,id,'destination',{destination,delivery_type:'port'}),/invalid/);
    await action(2,id,'destination',{destination,delivery_type:'door'});
    await assert.rejects(()=>action(1,id,'packing',{packing:{...packing,packages:[]},ready_at:future(1)}),/invalid/);
    await assert.rejects(()=>action(1,id,'packing',{packing:{...packing,packages:[{...packing.packages[0],count:1.5}]},ready_at:future(1)}),/invalid/);
    await assert.rejects(()=>action(1,id,'packing',{packing,ready_at:future(-1)}),/invalid_ready/);
    assert.equal((await action(1,id,'packing',{packing,ready_at:future(1)})).status,'awaiting_quote');
  });
  await check('quote bounds, stale edits, snapshots and persistent notifications',async()=>{
    for(const bad of [{freight:-1},{taxes:0.001},{expires_at:future(-1)},{estimated_days_min:8,estimated_days_max:4}])await assert.rejects(()=>action(6,id,'quote',{...quote(),...bad}));
    const before=await shipment(id),s=await action(6,id,'quote',quote());
    const q=await one('select * from shipping_quotes where id=$1',[s.current_quote_id]);
    assert.equal(q.total,'125.00');assert.deepEqual(q.destination_snapshot,destination);assert.deepEqual(q.packing_snapshot,packing);
    await assert.rejects(()=>action(6,id,'quote',quote(),before.revision),/stale/);
    assert((await as(2,"select * from shipping_notifications where kind='quote'")).length>0);
    const [notice]=await as(2,"select * from shipping_notifications where kind='quote'");
    await as(4,'select read_shipping_notifications($1,$2)',[id,notice.id]);
    assert.equal((await one('select read_at from shipping_notifications where id=$1',[notice.id])).read_at,null);
    await as(2,'select read_shipping_notifications($1,$2)',[id,notice.id]);
    assert((await one('select read_at from shipping_notifications where id=$1',[notice.id])).read_at);
  });
  await check('address changes invalidate quote; expired and replaced quotes cannot be accepted',async()=>{
    const old=await shipment(id);await action(2,id,'destination',{destination:{...destination,city:'Abu Dhabi'},delivery_type:'door'});
    await assert.rejects(()=>action(2,id,'accept',{quote_id:old.current_quote_id}),/stale/);
    const s=await action(6,id,'quote',quote());
    await db.query("update shipping_quotes set expires_at=now()-interval '1 second' where id=$1",[s.current_quote_id]);
    await assert.rejects(()=>action(2,id,'accept',{quote_id:s.current_quote_id}),/expired/);
    const newer=await action(6,id,'quote',quote());
    await assert.rejects(()=>action(2,id,'accept',{quote_id:s.current_quote_id}),/stale/);
    await assert.rejects(()=>action(1,id,'accept',{quote_id:newer.current_quote_id}),/access_denied/);
  });
  await check('acceptance uses stored price, never client total; repeat is idempotent',async()=>{
    const before=await shipment(id),data={quote_id:before.current_quote_id,freight:1,total:1};
    const s=await action(2,id,'accept',data);assert.equal(s.status,'booking_requested');assert.equal(s.booking_reference,null);
    const o=await one('select * from orders where id=$1',[id]);assert.equal(o.shipping,'125.00');assert.equal(o.total,'241.15');assert.equal(o.status,'awaiting_payment');
    assert.equal((await action(2,id,'accept',data,before.revision)).revision,s.revision);
    assert.equal((await one("select count(*)::int n from shipping_events where order_id=$1 and kind='accept'",[id])).n,1);
    await assert.rejects(()=>action(2,id,'destination',{destination,delivery_type:'door'}),/locked/);
    await assert.rejects(()=>action(6,id,'quote',quote()),/locked/);
    await assert.rejects(()=>action(2,id,'cancel'),/locked/);
    await assert.rejects(()=>as(2,'select * from mark_order_paid($1)',[id]),/access denied/);
    assert.equal((await as(1,'select * from mark_order_paid($1)',[id]))[0].status,'paid');
  });
  await check('confirmed booking requires admin, reference, and pickup after readiness',async()=>{
    await assert.rejects(()=>action(2,id,'book',{booking_reference:'fake',pickup_at:future(2)}),/access_denied/);
    await assert.rejects(()=>action(6,id,'book',{booking_reference:'B-1',pickup_at:future(0.5)}),/invalid_pickup/);
    await assert.rejects(()=>action(6,id,'book',{booking_reference:'',pickup_at:future(2)}),/invalid/);
    const payload={booking_reference:'BOOK-100',pickup_at:future(2)},s=await action(6,id,'book',payload);
    assert.equal(s.status,'booked');assert.equal(s.booking_reference,'BOOK-100');
    assert.equal((await action(6,id,'book',payload,0)).revision,s.revision);
  });
  await check('tracking follows carrier stages, cannot jump or bypass pickup, private timeline',async()=>{
    await assert.rejects(()=>action(6,id,'track',{status:'delivered',note:'Jump'}),/invalid_transition/);
    await assert.rejects(()=>action(6,id,'track',{status:'collected',note:'Early'}),/invalid_transition/);
    await db.query("update order_shipments set pickup_at=now()-interval '1 minute' where order_id=$1",[id]);
    for(const status of ['collected','departed','arrived','delivered']){
      await assert.rejects(()=>action(1,id,'track',{status,note:'Untrusted'}),/access_denied/);
      assert.equal((await action(6,id,'track',{status,note:'Received from carrier'})).status,status);
    }
    assert.equal((await as(4,'select * from shipping_events')).length,0);
    assert.equal((await as(4,'select * from shipping_quotes')).length,0);
  });
  await check('decline and pre-accept cancellation; new private offers use shipping quotes',async()=>{
    const o=await order(),s=await prepare(o.id);
    assert.equal((await action(2,o.id,'decline',{quote_id:s.current_quote_id})).status,'awaiting_quote');
    assert.equal((await action(2,o.id,'cancel')).status,'cancelled');
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'cancelled');
    const [q]=await as(1,"select * from create_private_chat_offer(1,1,10,12,7,'',$1)",[uid(++serial)]);
    assert.equal(q.shipping,'0.00');assert.equal(q.total,'139.38');assert.equal(q.shipping_pricing,'quote');
    const [accepted]=await as(2,'select * from accept_private_chat_offer($1)',[q.id]);
    assert.equal((await shipment(accepted.order_id)).status,'awaiting_details');
    assert.equal((await as(2,'select * from accept_private_chat_offer($1)',[q.id]))[0].order_id,accepted.order_id);
  });
  await db.exec("alter table profiles add full_name text default '',add phone text default '',add country_code text default ''");
  const domesticMigration=read('supabase/migrations/20260921100000_domestic_shipping_address.sql');
  await check('domestic migration works without the missing address table and secures its writes',async()=>{
    assert.equal((await one("select to_regclass('public.delivery_addresses') as relation")).relation,null);
    await db.exec(domesticMigration);await db.exec(domesticMigration);
    assert.equal((await one("select relrowsecurity from pg_class where oid='public.delivery_addresses'::regclass")).relrowsecurity,true);
    for(const sql of ['select * from delivery_addresses','select get_domestic_shipping_destination($1)']){
      await assert.rejects(()=>as(0,sql,sql.includes('$1')?[id]:[],'anon'),e=>e.code==='42501');
    }
    await assert.rejects(()=>as(2,'delete from delivery_addresses'),e=>e.code==='42501');
    const address={id:uid(++serial),label:'Home',address_line:'Riyadh',latitude:24.7,longitude:46.7};
    await assert.rejects(()=>as(5,'select * from save_delivery_address($1,$2)',[uid(5),address]),e=>e.code==='42501');
    await assert.rejects(()=>as(2,'select * from save_delivery_address($1,$2)',[uid(4),address]),/session_changed/);
    await as(4,'select * from save_delivery_address($1,$2)',[uid(4),address]);
    assert.equal((await as(2,'select * from delivery_addresses')).length,0);
    await as(4,'select * from delete_delivery_address($1,$2)',[uid(4),address.id]);
  });
  const savedDestination=async(user,oid)=>(await as(user,'select get_domestic_shipping_destination($1) as destination',[oid]))[0].destination;
  const saveDomestic=async(user,oid,expected,revision)=>(await as(user,'select * from set_domestic_shipping_destination($1,$2,$3)',[oid,revision??(await shipment(oid)).revision,expected]))[0];
  let localOrder,localAddress;
  await check('domestic address is private and missing addresses cannot produce empty shipments',async()=>{
    localOrder=await order();
    assert.equal(await savedDestination(2,localOrder.id),null);
    await assert.rejects(()=>saveDomestic(2,localOrder.id,{}),/saved_address_missing/);
    for(const user of [1,4,6]){
      await assert.rejects(()=>savedDestination(user,localOrder.id),/access_denied/);
      await assert.rejects(()=>saveDomestic(user,localOrder.id,{}),/access_denied/);
    }
    await assert.rejects(()=>as(0,'select get_domestic_shipping_destination($1)',[localOrder.id],'anon'),e=>e.code==='42501');
    await assert.rejects(()=>as(0,"select set_domestic_shipping_destination($1,0,'{}')",[localOrder.id],'anon'),e=>e.code==='42501');
    await db.query("insert into delivery_addresses(id,user_id,label,address_line,latitude,longitude,is_default) values($1,$2,'Other','Private foreign user address',24,46,true)",[uid(++serial),uid(4)]);
    assert.equal(await savedDestination(2,localOrder.id),null);
  });
  await check('domestic choice resolves the buyer default address and verifies contact details',async()=>{
    await db.query("insert into delivery_addresses(id,user_id,label,address_line,latitude,longitude,building,notes,is_default) values($1,$2,'Home','Riyadh, warehouse 12',24.7,46.7,'22','Call on arrival',true)",[uid(++serial),uid(2)]);
    await assert.rejects(()=>savedDestination(2,localOrder.id),/contact_missing/);
    await db.query("update profiles set full_name='Buyer',phone='501234567',country_code='+966' where id=$1",[uid(2)]);
    localAddress=await savedDestination(2,localOrder.id);
    assert.equal(localAddress.scope,'domestic');assert.equal(localAddress.country,'Saudi Arabia');
    assert.equal(localAddress.address,'Riyadh, warehouse 12 · 22');assert.equal(localAddress.delivery_notes,'Call on arrival');
    assert.equal(localAddress.contact,'Buyer');assert.equal(localAddress.phone_country_code,'+966');
    await assert.rejects(()=>saveDomestic(2,localOrder.id,{...localAddress,address:'Tampered'}),/stale/);
    const result=await saveDomestic(2,localOrder.id,localAddress);
    assert.deepEqual(result.destination,localAddress);assert.equal(result.delivery_type,'door');assert.equal(result.status,'awaiting_details');
    assert.equal((await saveDomestic(2,localOrder.id,localAddress)).revision,result.revision);
    await action(1,localOrder.id,'packing',{packing,ready_at:future(1)});
    const quoteState=await action(6,localOrder.id,'quote',quote());
    assert.equal((await one('select destination_snapshot from shipping_quotes where id=$1',[quoteState.current_quote_id])).destination_snapshot.scope,'domestic');
    await action(2,localOrder.id,'accept',{quote_id:quoteState.current_quote_id});
    await assert.rejects(()=>saveDomestic(2,localOrder.id,localAddress),/locked/);
  });
  await check('address changes require review and current shipping addresses survive default-address changes',async()=>{
    const next=await order(),before=await savedDestination(2,next.id);
    await db.query("update delivery_addresses set address_line='Jeddah, warehouse 99' where user_id=$1",[uid(2)]);
    await assert.rejects(()=>saveDomestic(2,next.id,before),/stale/);
    assert.equal((await savedDestination(2,localOrder.id)).address,localAddress.address);
    const fresh=await savedDestination(2,next.id);assert(fresh.address.startsWith('Jeddah'));
    await saveDomestic(2,next.id,fresh);
    assert.equal((await shipment(next.id)).current_quote_id,null);
    await assert.rejects(()=>saveDomestic(2,next.id,fresh,0),/stale/);
    await db.query('delete from delivery_addresses where user_id=$1',[uid(2)]);
    const another=await order(),fromHistory=await savedDestination(2,another.id);
    assert.equal(fromHistory.scope,'domestic');assert(!fromHistory.address.includes('Private foreign'));
  });
  await check('existing Saudi destinations are recognized and switching cancels an international quote',async()=>{
    const o=await order();
    await action(2,o.id,'destination',{destination:{...destination,country:'المملكة العربية السعودية',city:'Riyadh'},delivery_type:'door'});
    const current=await savedDestination(2,o.id);assert.equal(current.city,'Riyadh');
    await saveDomestic(2,o.id,current);
    await action(2,o.id,'destination',{destination:{...destination,scope:'international'},delivery_type:'door'});
    await action(1,o.id,'packing',{packing,ready_at:future(1)});
    await action(6,o.id,'quote',quote());
    const local=await savedDestination(2,o.id);
    const result=await saveDomestic(2,o.id,local);
    assert.equal(result.current_quote_id,null);assert.equal(result.status,'awaiting_quote');assert.equal(result.destination.scope,'domestic');
  });
  await check('rerunning address setup or domestic migration preserves existing addresses and shipments',async()=>{
    const beforeAddresses=(await db.query('select * from delivery_addresses order by user_id,id')).rows;
    const beforeShipments=(await db.query('select * from order_shipments order by order_id')).rows;
    // قواعد سبق أن طبّقت هجرة العناوين الأصلية تظل متوافقة مع الملف الكامل.
    await db.exec(read('supabase/migrations/20260910060000_delivery_addresses.sql'));
    await db.exec(domesticMigration);
    assert.deepEqual((await db.query('select * from delivery_addresses order by user_id,id')).rows,beforeAddresses);
    assert.deepEqual((await db.query('select * from order_shipments order by order_id')).rows,beforeShipments);
  });
  await check('structured addresses save separate fields and validate national formats without changing RLS',async()=>{
    const migration=read('supabase/migrations/20260921160000_structured_delivery_addresses.sql');
    await db.exec(migration);await db.exec(migration);
    const value={id:uid(++serial),latitude:24.7,longitude:46.7,address_scope:'domestic',country:'السعودية',city:'Riyadh',district:'District',street:'Street',building:'١٢٣٤',short_address:'abcd١٢٣٤',postal_code:'١٢٣٤٥',additional_number:'٥٦٧٨'};
    const save=async(user,data,expected=uid(user))=>as(user,'select * from save_structured_delivery_address($1,$2)',[expected,data]);
    const rows=await save(2,value),saved=rows.find(r=>r.id===value.id);
    assert.equal(saved.short_address,'ABCD1234');assert.equal(saved.postal_code,'12345');assert.equal(saved.additional_number,'5678');assert.equal(saved.street,'Street');assert.equal(saved.country,'Saudi Arabia');
    assert(saved.address_line.includes('12345'));assert(saved.address_line.includes('ABCD1234'));
    for(const extra of [{postal_code:'123'},{short_address:'invalid'},{additional_number:'12'},{building:'12'},{city:''},{country:'UAE'},{district:{bad:true}}])await assert.rejects(()=>save(2,{...value,...extra}),e=>e.code==='22023');
    await assert.rejects(()=>save(4,value,uid(2)),e=>e.code==='42501');
    await assert.rejects(()=>save(5,value),e=>e.code==='42501');
    await assert.rejects(()=>as(0,'select * from save_structured_delivery_address($1,$2)',[uid(2),value],'anon'),e=>e.code==='42501');
    assert.equal((await as(4,'select * from delivery_addresses where id=$1',[value.id])).length,0);
    const o=await order(),dest=await savedDestination(2,o.id);
    assert.equal(dest.city,'Riyadh');assert.equal(dest.postal_code,'12345');assert.equal(dest.short_address,'ABCD1234');
    await saveDomestic(2,o.id,dest);
    const foreign={...value,address_scope:'international',country:'France',city:'Paris',district:'Centre'};
    const updated=(await save(2,foreign)).find(r=>r.id===value.id);
    for(const key of ['street','short_address','postal_code','additional_number','building','floor','apartment','notes'])assert.equal(updated[key],'');
    assert.equal(updated.address_line,'France، Paris، Centre');
    const next=await order();await assert.rejects(()=>savedDestination(2,next.id),/saved_address_not_domestic/);
    assert.equal((await savedDestination(2,o.id)).short_address,'ABCD1234');
    const before=(await as(2,'select * from delivery_addresses')).map(r=>({...r}));
    await db.exec(migration);
    assert.deepEqual(await as(2,'select * from delivery_addresses'),before);
    // العميل القديم يستطيع الحفظ، لكن يُطلب مراجعة الأجزاء قبل شحن محلي جديد.
    await as(2,'select * from save_delivery_address($1,$2)',[uid(2),{id:value.id,label:'Legacy edit',address_line:'New location',latitude:48.8,longitude:2.3}]);
    const legacy=await one('select * from delivery_addresses where user_id=$1 and id=$2',[uid(2),value.id]);
    assert.equal(legacy.address_scope,'legacy_review');assert.equal(legacy.city,'');
    await assert.rejects(()=>savedDestination(2,next.id),/saved_address_not_domestic/);
  });
  const previewSaved=async(user,oid)=>(await as(user,'select get_saved_shipping_destination($1) as destination',[oid]))[0].destination;
  const linkSaved=async(user,oid,dest,revision)=>(await as(user,'select * from link_saved_shipping_address($1,$2,$3)',[oid,revision??(await shipment(oid)).revision,dest]))[0];
  await check('linking a saved address replaces only the selected shipment and invalidates its quote',async()=>{
    const migration=read('supabase/migrations/20260921200000_link_saved_shipping_address.sql');
    const before=(await db.query('select * from order_shipments order by order_id')).rows;
    await db.exec(migration);await db.exec(migration);
    assert.deepEqual((await db.query('select * from order_shipments order by order_id')).rows,before);
    const o=await order(),original=await prepare(o.id);
    await assert.rejects(()=>previewSaved(2,o.id),/saved_address_not_domestic/);
    const address={id:uid(++serial),latitude:21.5,longitude:39.2,address_scope:'domestic',country:'السعودية',city:'Jeddah',district:'District',street:'New Street',building:'1234',short_address:'ABCD1234',postal_code:'12345',additional_number:'5678'};
    await as(2,'select * from save_structured_delivery_address($1,$2)',[uid(2),address]);
    const preview=await previewSaved(2,o.id);
    assert.equal(preview.saved_address_id,address.id);assert.equal(preview.short_address,'ABCD1234');
    assert.equal((await shipment(o.id)).destination.country,'UAE');
    await assert.rejects(()=>linkSaved(2,o.id,{...preview,address:'Tampered'}),/stale/);
    await assert.rejects(()=>linkSaved(2,o.id,preview,0),/stale/);
    const linked=await linkSaved(2,o.id,preview);
    assert.deepEqual(linked.destination,preview);assert.equal(linked.delivery_type,'door');
    assert.equal(linked.current_quote_id,null);assert.equal(linked.status,'awaiting_quote');
    assert.equal(linked.revision,original.revision+1);
    const requoted=await action(6,o.id,'quote',quote());
    const events=(await one('select count(*)::int n from shipping_events where order_id=$1',[o.id])).n;
    assert.equal((await linkSaved(2,o.id,preview)).revision,requoted.revision);
    assert.equal((await shipment(o.id)).current_quote_id,requoted.current_quote_id);
    assert.equal((await one('select count(*)::int n from shipping_events where order_id=$1',[o.id])).n,events);
    await as(2,'select * from save_structured_delivery_address($1,$2)',[uid(2),{...address,street:'Changed Street'}]);
    await assert.rejects(()=>linkSaved(2,o.id,preview),/stale/);
    assert.deepEqual((await shipment(o.id)).destination,preview);
    const fresh=await previewSaved(2,o.id);assert.equal(fresh.street,'Changed Street');
    const changed=await linkSaved(2,o.id,fresh);assert.equal(changed.current_quote_id,null);
    for(const user of [1,4,5,6]){
      await assert.rejects(()=>previewSaved(user,o.id),/access_denied/);
      await assert.rejects(()=>linkSaved(user,o.id,fresh),/access_denied/);
    }
    await assert.rejects(()=>as(0,'select get_saved_shipping_destination($1)',[o.id],'anon'),e=>e.code==='42501');
    await assert.rejects(()=>as(0,"select link_saved_shipping_address($1,0,'{}')",[o.id],'anon'),e=>e.code==='42501');
    const accepted=await action(6,o.id,'quote',quote());await action(2,o.id,'accept',{quote_id:accepted.current_quote_id});
    await assert.rejects(()=>linkSaved(2,o.id,fresh),/locked/);
    const other=await order();await db.query('delete from delivery_addresses where user_id=$1',[uid(2)]);
    await assert.rejects(()=>previewSaved(2,other.id),/saved_address_missing/);
    assert.deepEqual((await shipment(o.id)).destination,fresh);
  });
  const approvalMigration=read('supabase/migrations/20260921220000_shipping_approval_sequence.sql');
  await check('approval migration preserves historical prices and quotes and initializes confirmations once',async()=>{
    const before=(await db.query('select order_id,status,destination,packing,current_quote_id from order_shipments order by order_id')).rows;
    const prices=(await db.query('select id,total,shipping,status from orders order by id')).rows;
    await db.exec(approvalMigration);await db.exec(approvalMigration);
    assert.deepEqual((await db.query('select order_id,status,destination,packing,current_quote_id from order_shipments order by order_id')).rows,before);
    assert.deepEqual((await db.query('select id,total,shipping,status from orders order by id')).rows,prices);
    for(const row of before){const s=await shipment(row.order_id);assert.equal(!!s.buyer_confirmed_at,!!row.destination);assert.equal(!!s.factory_confirmed_at,!!row.destination&&!!row.packing);}
  });
  await check('buyer then factory then carrier quote then payment; address edits require factory reconfirmation',async()=>{
    const o=await order();let s=await shipment(o.id);
    assert.equal(s.buyer_confirmed_at,null);assert.equal(s.factory_confirmed_at,null);
    assert.deepEqual((await db.query('select recipient_id,kind from shipping_notifications where order_id=$1',[o.id])).rows,[{recipient_id:uid(2),kind:'buyer_details_needed'}]);
    await assert.rejects(()=>action(1,o.id,'packing',{packing,ready_at:future(1)}),/buyer_confirmation_required/);
    await assert.rejects(()=>action(6,o.id,'quote',quote()),/factory_confirmation_required/);
    s=await action(2,o.id,'destination',{destination,delivery_type:'door'});
    assert(s.buyer_confirmed_at);assert.equal(s.factory_confirmed_at,null);assert.equal(s.status,'awaiting_details');
    const notice=await one("select recipient_id from shipping_notifications where order_id=$1 and kind='destination'",[o.id]);assert.equal(notice.recipient_id,uid(1));
    await assert.rejects(()=>action(2,o.id,'packing',{packing,ready_at:future(1)}),/access_denied/);
    s=await action(1,o.id,'packing',{packing,ready_at:future(1)});assert(s.factory_confirmed_at);assert.equal(s.status,'awaiting_quote');
    const adminNotice=await one("select recipient_id from shipping_notifications where order_id=$1 and kind='packing'",[o.id]);assert.equal(adminNotice.recipient_id,uid(6));
    s=await action(6,o.id,'quote',quote());const previousQuote=s.current_quote_id;
    assert.equal((await action(2,o.id,'destination',{destination,delivery_type:'door'})).revision,s.revision);
    s=await action(2,o.id,'destination',{destination:{...destination,address:'New warehouse'},delivery_type:'door'});
    assert.equal(s.factory_confirmed_at,null);assert.equal(s.status,'awaiting_details');assert.equal(s.current_quote_id,null);assert.deepEqual(s.packing,packing);
    await db.exec(approvalMigration);assert.equal((await shipment(o.id)).factory_confirmed_at,null);
    await assert.rejects(()=>action(6,o.id,'quote',quote()),/factory_confirmation_required/);
    await assert.rejects(()=>action(2,o.id,'accept',{quote_id:previousQuote}),/stale/);
    s=await action(1,o.id,'packing',{packing,ready_at:s.ready_at});assert(s.factory_confirmed_at);
    s=await action(6,o.id,'quote',quote());await action(2,o.id,'accept',{quote_id:s.current_quote_id});
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'awaiting_payment');
    await assert.rejects(()=>action(6,o.id,'book',{booking_reference:'PREMATURE',pickup_at:future(2)}),/payment_required/);
    await assert.rejects(()=>as(2,'select * from mark_order_paid($1)',[o.id]),/access denied/i);
    await as(1,'select * from mark_order_paid($1)',[o.id]);
    assert.equal((await one("select count(*)::int n from shipping_events where order_id=$1 and kind='payment'",[o.id])).n,1);
    assert.equal((await action(6,o.id,'book',{booking_reference:'PAID-BOOKING',pickup_at:future(2)})).status,'booked');
    await assert.rejects(()=>action(2,o.id,'destination',{destination,delivery_type:'door'}),/locked/);
  });
  await check('both saved-address paths enforce the same sequence and reset factory approval',async()=>{
    const value={id:uid(++serial),latitude:24.7,longitude:46.7,address_scope:'domestic',country:'السعودية',city:'Riyadh',district:'District'};
    await as(2,'select * from save_structured_delivery_address($1,$2)',[uid(2),value]);
    const o=await order();let dest=await savedDestination(2,o.id),s=await saveDomestic(2,o.id,dest);
    assert(s.buyer_confirmed_at);assert.equal(s.factory_confirmed_at,null);
    await action(1,o.id,'packing',{packing,ready_at:future(1)});s=await action(6,o.id,'quote',quote());
    const unchanged=await saveDomestic(2,o.id,dest);assert.equal(unchanged.current_quote_id,s.current_quote_id);assert(unchanged.factory_confirmed_at);
    await as(2,'select * from save_structured_delivery_address($1,$2)',[uid(2),{...value,city:'Jeddah'}]);
    dest=await previewSaved(2,o.id);s=await linkSaved(2,o.id,dest);
    assert.equal(s.factory_confirmed_at,null);assert.equal(s.status,'awaiting_details');assert.equal(s.current_quote_id,null);assert.deepEqual(s.packing,packing);
    await assert.rejects(()=>action(6,o.id,'quote',quote()),/factory_confirmation_required/);
    await action(1,o.id,'packing',{packing,ready_at:s.ready_at});
    s=await action(6,o.id,'quote',quote());assert(s.current_quote_id);
    await action(2,o.id,'destination',{destination,delivery_type:'door'});
    s=await saveDomestic(2,o.id,await savedDestination(2,o.id));assert.equal(s.factory_confirmed_at,null);assert.equal(s.status,'awaiting_details');
  });
  await check('private packing images enforce ownership, confirmation, limits, snapshot access and immutable storage',async()=>{
    await db.exec(`create table storage.buckets(id text primary key,name text,public bool,file_size_limit bigint,allowed_mime_types text[]);
      alter table storage.objects add bucket_id text,add name text,add metadata jsonb;
      alter table storage.objects enable row level security;
      grant usage on schema storage to authenticated;
      grant select,insert,update,delete on storage.objects to authenticated;
      create policy unrelated_broad_access on storage.objects for all to authenticated using(true) with check(true);`);
    const migration=read('supabase/migrations/20260921230000_shipping_package_images.sql');await db.exec(migration);await db.exec(migration);
    const bucket=await one("select * from storage.buckets where id='shipment-images'");assert.equal(bucket.public,false);assert.equal(Number(bucket.file_size_limit),5242880);
    const o=await order(),other=await order();
    const path=o.id+'/'+uid(++serial)+'.jpg',foreign=other.id+'/'+uid(++serial)+'.jpg';
    const upload=(user,name)=>as(user,"insert into storage.objects(bucket_id,name,metadata) values('shipment-images',$1,'{\"mimetype\":\"image/jpeg\"}')",[name]);
    await assert.rejects(()=>upload(1,path),e=>e.code==='42501');
    await action(2,o.id,'destination',{destination,delivery_type:'door'});
    await action(2,other.id,'destination',{destination,delivery_type:'door'});
    for(const user of [2,3,4,5,6])await assert.rejects(()=>upload(user,path),e=>e.code==='42501');
    await assert.rejects(()=>upload(1,o.id+'/bad.svg'),e=>e.code==='42501');
    await upload(1,path);await upload(1,foreign);
    const view=user=>as(user,"select name from storage.objects where bucket_id='shipment-images' and name=$1",[path]);
    assert.equal((await view(1)).length,1);assert.equal((await view(2)).length,0);assert.equal((await view(4)).length,0);
    const withPhotos=photos=>({...packing,packages:[{...packing.packages[0],photos}]});
    for(const photos of [[foreign],[o.id+'/'+uid(++serial)+'.jpg'],['https://example.com/photo.jpg'],[{}],Array(6).fill(path),'not-array']){
      await assert.rejects(()=>action(1,o.id,'packing',{packing:withPhotos(photos),ready_at:future(1)}),/shipping_(invalid_images|image_limit)/);
    }
    await assert.rejects(()=>action(1,o.id,'packing',{packing:{...packing,packages:Array(5).fill({...packing.packages[0],photos:Array(5).fill(path)})},ready_at:future(1)}),/image_limit/);
    await action(1,o.id,'packing',{packing:withPhotos([path]),ready_at:future(1)});
    assert.equal((await view(2)).length,1);assert.equal((await view(4)).length,0);assert.equal((await view(6)).length,1);
    const quoteState=await action(6,o.id,'quote',quote());
    assert.equal((await one('select packing_snapshot from shipping_quotes where id=$1',[quoteState.current_quote_id])).packing_snapshot.packages[0].photos[0],path);
    await action(1,o.id,'packing',{packing:withPhotos([]),ready_at:future(1)});
    assert.equal((await view(2)).length,1);
    assert.equal((await as(1,"delete from storage.objects where bucket_id='shipment-images' and name=$1 returning name",[path])).length,0);
    assert.equal((await as(1,"update storage.objects set metadata='{}' where bucket_id='shipment-images' and name=$1 returning name",[path])).length,0);
    const q=await action(6,o.id,'quote',quote());await action(2,o.id,'accept',{quote_id:q.current_quote_id});
    await assert.rejects(()=>upload(1,o.id+'/'+uid(++serial)+'.jpg'),e=>e.code==='42501');
    await assert.rejects(()=>as(0,"select * from storage.objects where bucket_id='shipment-images'",[],'anon'),e=>e.code==='42501');
  });
  await check('factory pickup readiness requires payment and ownership; notifies admin once and gates booking',async()=>{
    const migration=read('supabase/migrations/20260922090000_factory_pickup_readiness.sql');
    const prior=(await db.query('select order_id,status,revision from order_shipments order by order_id')).rows;
    await db.exec(migration);await db.exec(migration);
    assert.deepEqual((await db.query('select order_id,status,revision from order_shipments order by order_id')).rows,prior);
    assert.equal((await one('select count(*)::int n from order_shipments where pickup_ready_at is not null')).n,0);
    const o=await order();let s=await prepare(o.id);
    const ready=async(user,revision)=>(await as(user,'select * from confirm_shipping_pickup_ready($1,$2)',[o.id,revision??(await shipment(o.id)).revision]))[0];
    await assert.rejects(()=>ready(1),/payment_required/);
    await action(2,o.id,'accept',{quote_id:s.current_quote_id});
    await assert.rejects(()=>ready(1),/payment_required/);
    for(const user of [2,3,4,5,6])await assert.rejects(()=>ready(user),/access_denied/);
    await assert.rejects(()=>as(0,'select confirm_shipping_pickup_ready($1,0)',[o.id],'anon'),e=>e.code==='42501');
    await as(6,'select * from mark_order_paid($1)',[o.id]);
    const notices=(await db.query("select recipient_id from shipping_notifications where order_id=$1 and kind='pickup_ready_needed'",[o.id])).rows;
    assert.deepEqual(notices,[{recipient_id:uid(1)}]);
    await assert.rejects(()=>action(6,o.id,'book',{booking_reference:'TOO-EARLY',pickup_at:future(2)}),/pickup_ready_required/);
    assert.equal((await shipment(o.id)).booking_reference,null);
    await assert.rejects(()=>ready(1,0),/stale/);
    const before=await shipment(o.id),confirmed=await ready(1,before.revision);
    assert(confirmed.pickup_ready_at);assert.equal(confirmed.status,'booking_requested');assert.equal(confirmed.revision,before.revision+1);
    const snapshot=await one('select total,shipping,status from orders where id=$1',[o.id]);
    assert.equal(snapshot.status,'paid');assert.equal(snapshot.total,'241.15');
    const repeated=await ready(1,before.revision);assert.equal(repeated.revision,confirmed.revision);assert.deepEqual(repeated.pickup_ready_at,confirmed.pickup_ready_at);
    assert.equal((await one("select count(*)::int n from shipping_events where order_id=$1 and kind='pickup_ready'",[o.id])).n,1);
    assert.deepEqual((await db.query("select recipient_id from shipping_notifications where order_id=$1 and kind='pickup_ready'",[o.id])).rows,[{recipient_id:uid(6)}]);
    assert.equal((await as(4,"select * from shipping_notifications where order_id=$1",[o.id])).length,0);
    assert.equal((await action(6,o.id,'book',{booking_reference:'READY-BOOKING',pickup_at:future(2)})).status,'booked');
    await db.exec(migration);assert.deepEqual((await shipment(o.id)).pickup_ready_at,confirmed.pickup_ready_at);
    assert.deepEqual((await ready(1)).pickup_ready_at,confirmed.pickup_ready_at);
    const cancelled=await order();await action(2,cancelled.id,'cancel');
    await assert.rejects(async()=>as(1,'select confirm_shipping_pickup_ready($1,$2)',[cancelled.id,(await shipment(cancelled.id)).revision]),/locked/);
  });
  await check('paid factory production starts and completes once before pickup readiness',async()=>{
    const migration=read('supabase/migrations/20260922100000_shipping_production_stage.sql');
    const before=(await db.query('select order_id,status,pickup_ready_at,revision from order_shipments order by order_id')).rows;
    await db.exec(migration);await db.exec(migration);
    assert.deepEqual((await db.query('select order_id,status,pickup_ready_at,revision from order_shipments order by order_id')).rows,before);
    assert.equal((await one('select count(*)::int n from order_shipments where production_started_at is not null')).n,0);
    const o=await order();let s=await prepare(o.id);
    const production=async(user,act,revision)=>(await as(user,'select * from update_shipping_production($1,$2,$3)',[o.id,revision??(await shipment(o.id)).revision,act]))[0];
    await assert.rejects(()=>production(1,'start'),/payment_required/);
    await action(2,o.id,'accept',{quote_id:s.current_quote_id});
    await assert.rejects(()=>production(1,'start'),/payment_required/);
    await as(6,'select * from mark_order_paid($1)',[o.id]);
    assert.deepEqual((await db.query("select recipient_id from shipping_notifications where order_id=$1 and kind='production_needed'",[o.id])).rows,[{recipient_id:uid(1)}]);
    for(const user of [2,3,4,5,6])await assert.rejects(()=>production(user,'start'),/access_denied/);
    await assert.rejects(()=>as(0,"select update_shipping_production($1,0,'start')",[o.id],'anon'),e=>e.code==='42501');
    await assert.rejects(()=>production(1,'invalid'),/invalid_action/);
    await assert.rejects(()=>production(1,'complete'),/production_start_required/);
    await assert.rejects(()=>production(1,'start',0),/stale/);
    const pre=await shipment(o.id);s=await production(1,'start',pre.revision);
    assert(s.production_started_at);assert.equal(s.production_completed_at,null);
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'processing');
    assert.equal((await production(1,'start',pre.revision)).revision,s.revision);
    await db.exec(migration);assert.deepEqual((await shipment(o.id)).production_started_at,s.production_started_at);
    await assert.rejects(()=>as(1,'select confirm_shipping_pickup_ready($1,$2)',[o.id,s.revision]),/production_required/);
    assert.equal((await shipment(o.id)).pickup_ready_at,null);
    const active=s;s=await production(1,'complete');assert(s.production_completed_at);assert(s.production_completed_at>=s.production_started_at);
    assert.equal((await production(1,'complete',active.revision)).revision,s.revision);
    for(const kind of ['production_started','production_completed']){
      assert.equal((await one('select count(*)::int n from shipping_events where order_id=$1 and kind=$2',[o.id,kind])).n,1);
      assert.deepEqual((await db.query('select recipient_id from shipping_notifications where order_id=$1 and kind=$2',[o.id,kind])).rows,[{recipient_id:uid(2)}]);
    }
    s=(await as(1,'select * from confirm_shipping_pickup_ready($1,$2)',[o.id,s.revision]))[0];assert(s.pickup_ready_at);
    assert.equal((await action(6,o.id,'book',{booking_reference:'PRODUCTION-DONE',pickup_at:future(2)})).status,'booked');
    assert.equal((await one('select total from orders where id=$1',[o.id])).total,'241.15');
  });
  await check('public sales start only at confirmed payment and survive fulfilment',async()=>{
    const migration=read('supabase/migrations/20260923090000_paid_sales_stats.sql');
    const snapshots=(await db.query('select * from orders order by id')).rows;
    await db.exec(migration);await db.exec(migration);
    assert.deepEqual((await db.query('select * from orders order by id')).rows,snapshots,'Migration never marks orders paid or changes totals');
    const stats=async(role='anon')=>(await as(0,'select * from get_public_stats()',[],role))[0];
    const initial=await stats();
    assert.deepEqual(Object.keys(initial),['factories_count','products_count','units_sold','revenue']);
    assert.deepEqual(await stats('authenticated'),initial);
    await assert.rejects(()=>as(0,'select * from orders',[],'anon'),e=>e.code==='42501');
    const o=await order();
    assert.equal(o.status,'awaiting_shipping');
    await action(2,o.id,'destination',{destination,delivery_type:'door'});
    assert.deepEqual(await stats(),initial,'Stage two, awaiting factory confirmation, is not a sale');
    await action(1,o.id,'packing',{packing,ready_at:future(1)});
    const s=await action(6,o.id,'quote',quote());
    await action(2,o.id,'accept',{quote_id:s.current_quote_id});
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'awaiting_payment');
    assert.deepEqual(await stats(),initial,'Quote approval is not payment');
    await as(6,'select * from mark_order_paid($1)',[o.id]);
    const paid=await stats();
    const total=Number((await one('select total from orders where id=$1',[o.id])).total);
    assert.equal(Number(paid.units_sold)-Number(initial.units_sold),10);
    assert.equal(Math.round((Number(paid.revenue)-Number(initial.revenue))*100),Math.round(total*100));
    assert.equal(paid.factories_count,initial.factories_count);
    assert.equal(paid.products_count,initial.products_count);
    // Multiple order lines must not multiply the order's monetary total.
    await db.query('update order_items set quantity=4 where order_id=$1',[o.id]);
    await db.query("insert into order_items(order_id,product_id,product_name,unit_price,quantity,line_total) values($1,1,'Additional line',10,6,60)",[o.id]);
    assert.deepEqual(await stats(),paid);
    for(const status of ['pending','awaiting_shipping','awaiting_payment','cancelled','payment_failed','paid','processing','shipped','completed']){
      await db.query('update orders set status=$2 where id=$1',[o.id,status]);
      assert.deepEqual(await stats(),['paid','processing','shipped','completed'].includes(status)?paid:initial,status);
    }
    await db.exec('begin');
    await db.exec("update orders set status='awaiting_payment'");
    const empty=await one('select * from get_public_stats()');
    assert.equal(Number(empty.units_sold),0);assert.equal(Number(empty.revenue),0);
    assert.equal(empty.factories_count,initial.factories_count);
    await db.exec('rollback');
  });
  const returnMigration=read('supabase/migrations/20260926090000_shipping_return_stage.sql');
  const beforeReturnMigration=(await db.query('select * from order_shipments order by order_id')).rows;
  await db.exec(returnMigration);await db.exec(returnMigration);
  assert.deepEqual((await db.query('select * from order_shipments order by order_id')).rows,beforeReturnMigration);
  const back=async(user,id,stage,reason='Correct the previous details',revision)=>(await as(user,
    'select * from return_shipping_stage($1,$2,$3,$4)',[id,revision??(await shipment(id)).revision,stage,reason]))[0];
  await check('return authorization, reason, revision and payment boundary are enforced by the server',async()=>{
    const o=await order();
    await assert.rejects(()=>as(0,'select return_shipping_stage($1,0,2,$2)',[o.id,'Correct'],'anon'),e=>e.code==='42501');
    for(const user of [0,3,4,5])await assert.rejects(()=>back(user,o.id,1),/access_denied/);
    await assert.rejects(()=>back(2,o.id,1),/locked/);
    await action(2,o.id,'destination',{destination,delivery_type:'door'});
    for(const reason of ['', '   ', 'x'.repeat(1001)])await assert.rejects(()=>back(2,o.id,2,reason),/reason_required/);
    await assert.rejects(()=>back(2,o.id,2,'Correction',0),/stale/);
    await assert.rejects(()=>back(2,o.id,3),/stale/);
    const previous=await shipment(o.id),returned=await back(1,o.id,2);
    assert.equal(returned.buyer_confirmed_at,null);assert.deepEqual(returned.destination,previous.destination);
    assert.equal(returned.revision,previous.revision+1);
    await assert.rejects(()=>back(1,o.id,2,'Correction',previous.revision),/stale/);
    await assert.rejects(()=>action(1,o.id,'packing',{packing,ready_at:future(1)}),/buyer_confirmation_required/);
    const event=await one("select * from shipping_events where order_id=$1 and kind='returned_to_stage_1'",[o.id]);
    assert.equal(event.note,'Correct the previous details');assert.equal(event.actor_id,uid(1));
    assert.equal(event.return_details.from_stage,2);assert.equal(event.return_details.to_stage,1);
    assert(event.return_details.shipment.buyer_confirmed_at);
    assert((await as(2,"select * from shipping_notifications where order_id=$1 and kind='returned_to_stage_1'",[o.id])).length);
  });
  await check('pre-payment returns preserve drafts and quote history while invalidating acceptance',async()=>{
    const o=await order();await prepare(o.id);let s=await shipment(o.id);const quoteId=s.current_quote_id;
    await action(2,o.id,'accept',{quote_id:quoteId});
    s=await back(2,o.id,4);
    assert.equal(s.status,'awaiting_quote');assert.equal(s.current_quote_id,null);
    assert(s.factory_confirmed_at);assert.deepEqual(s.packing,packing);
    const changed=await one('select * from orders where id=$1',[o.id]);
    assert.equal(changed.status,'awaiting_shipping');assert.equal(changed.shipping,'0.00');assert.equal(changed.total,'116.15');
    assert((await one('select accepted_at from shipping_quotes where id=$1',[quoteId])).accepted_at);
    await assert.rejects(()=>as(1,'select mark_order_paid($1)',[o.id]),/not awaiting payment/);
    s=await back(6,o.id,3);assert.equal(s.status,'awaiting_details');assert.equal(s.factory_confirmed_at,null);assert(s.buyer_confirmed_at);
    await assert.rejects(()=>action(6,o.id,'quote',quote()),/factory_confirmation_required/);
    await action(1,o.id,'packing',{packing,ready_at:future(1)});await action(6,o.id,'quote',quote());
    s=await shipment(o.id);assert.notEqual(s.current_quote_id,quoteId);
    await action(2,o.id,'accept',{quote_id:s.current_quote_id});await as(1,'select mark_order_paid($1)',[o.id]);
    await assert.rejects(()=>back(6,o.id,5),/payment_locked/);
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'paid');
  });
  await check('paid production, readiness, collection and delivery corrections keep payment and sales intact',async()=>{
    const o=await order();await prepare(o.id);let s=await shipment(o.id);
    await action(2,o.id,'accept',{quote_id:s.current_quote_id});await as(1,'select mark_order_paid($1)',[o.id]);
    const totals=await one('select total,shipping,payment_fee,vat_amount from orders where id=$1',[o.id]);
    const stats=await one('select * from get_public_stats()');
    const production=async act=>as(1,'select update_shipping_production($1,$2,$3)',[o.id,(await shipment(o.id)).revision,act]);
    const ready=async()=>as(1,'select confirm_shipping_pickup_ready($1,$2)',[o.id,(await shipment(o.id)).revision]);
    await production('start');await production('complete');
    await assert.rejects(()=>back(2,o.id,6),/access_denied/);
    s=await back(1,o.id,6);assert.equal(s.production_completed_at,null);assert(s.production_started_at);
    await assert.rejects(ready,/production_required/);
    await production('complete');await ready();s=await back(1,o.id,7);assert.equal(s.pickup_ready_at,null);
    await ready();await action(6,o.id,'book',{booking_reference:'BOOK-RETURN',pickup_at:future(2)});
    await assert.rejects(()=>back(1,o.id,7),/access_denied/);
    s=await back(6,o.id,7);assert.equal(s.booking_reference,null);assert.equal(s.pickup_at,null);assert.equal(s.status,'booking_requested');
    const bookingHistory=await one("select return_details from shipping_events where order_id=$1 and kind='returned_to_stage_6' order by id desc limit 1",[o.id]);
    assert.equal(bookingHistory.return_details.shipment.booking_reference,'BOOK-RETURN');
    await ready();await action(6,o.id,'book',{booking_reference:'BOOK-FIXED',pickup_at:future(2)});
    await db.query('update order_shipments set pickup_at=$2 where order_id=$1',[o.id,future(-1)]);
    await action(6,o.id,'track',{status:'collected',note:'Collected'});
    s=await back(6,o.id,8);assert.equal(s.status,'booked');assert(s.pickup_ready_at);
    for(const status of ['collected','departed','arrived','delivered'])await action(6,o.id,'track',{status,note:status});
    await assert.rejects(()=>back(2,o.id,9),/access_denied/);
    s=await back(6,o.id,9);assert.equal(s.status,'arrived');
    assert.equal((await one('select status from orders where id=$1',[o.id])).status,'shipped');
    assert.deepEqual(await one('select total,shipping,payment_fee,vat_amount from orders where id=$1',[o.id]),totals);
    assert.deepEqual(await one('select * from get_public_stats()'),stats);
    await action(6,o.id,'track',{status:'delivered',note:'Corrected delivery'});
    const cancelled=await order();await action(2,cancelled.id,'cancel');
    await assert.rejects(()=>back(6,cancelled.id,2),/locked/);
  });
  const exportMigration=read('supabase/migrations/20260926100000_shipping_export_preferences.sql');
  const beforeExport=(await db.query('select * from order_shipments order by order_id')).rows;
  await db.exec(exportMigration);await db.exec(exportMigration);
  assert.deepEqual((await db.query('select * from order_shipments order by order_id')).rows,beforeExport);
  const preferences={version:1,transport_mode:'sea',sea_service:'fcl',container_type:'40ft_hc',container_count:2,delivery_route:'port_to_port',origin_terminal:'Jeddah',incoterm:'FOB',incoterms_version:'2020',named_place:'Jeddah'};
  const exportDestination={...destination,scope:'international',port:'Dubai',phone:'544569187',phone_country_code:'+966',phone_country_iso:'SA',export_preferences:preferences};
  await check('export preferences enforce mode, service, route, containers and trade terms on the server',async()=>{
    const o=await order();
    for(const changes of [{version:2},{transport_mode:'invalid'},{sea_service:'invalid'},{container_type:'invalid'},{container_count:0},{container_count:1.5},{container_count:1001},{container_count:'2'},{container_count:null},{delivery_route:'invalid'},{origin_terminal:''},{named_place:'   '},{named_place:{}},{incoterm:'invalid'},{incoterms_version:'2010'},{transport_mode:'air',sea_service:null,container_type:null,container_count:null}]){
      await assert.rejects(()=>action(2,o.id,'destination',{destination:{...exportDestination,export_preferences:{...preferences,...changes}},delivery_type:'port'}),/invalid_export_preferences/);
    }
    await assert.rejects(()=>action(2,o.id,'destination',{destination:exportDestination,delivery_type:'door'}),/invalid_export_preferences/);
    await assert.rejects(()=>action(1,o.id,'destination',{destination:exportDestination,delivery_type:'port'}),/access_denied/);
    await action(2,o.id,'destination',{destination:exportDestination,delivery_type:'port'});
    assert.deepEqual((await shipment(o.id)).destination.export_preferences,preferences);
    assert.equal((await shipment(o.id)).destination.phone_country_code,'+966');assert.equal((await shipment(o.id)).destination.phone,'544569187');
    for(const mode of ['air','road','rail','express','multimodal']){
      const pref={...preferences,transport_mode:mode,sea_service:null,container_type:null,container_count:null,incoterm:'FCA'};
      await action(2,o.id,'destination',{destination:{...exportDestination,export_preferences:pref},delivery_type:'port'});
      assert.equal((await shipment(o.id)).destination.export_preferences.transport_mode,mode);
    }
  });
  await check('export changes invalidate factory approval and quotes while preserving quote snapshots',async()=>{
    const o=await order();await action(2,o.id,'destination',{destination:exportDestination,delivery_type:'port'});
    await action(1,o.id,'packing',{packing,ready_at:future(1)});await action(6,o.id,'quote',quote());
    let s=await shipment(o.id);const quoteId=s.current_quote_id;
    assert.deepEqual((await one('select destination_snapshot from shipping_quotes where id=$1',[quoteId])).destination_snapshot.export_preferences,preferences);
    const phoneSnapshot=(await one('select destination_snapshot from shipping_quotes where id=$1',[quoteId])).destination_snapshot;
    assert.equal(phoneSnapshot.phone_country_code,'+966');assert.equal(phoneSnapshot.phone_country_iso,'SA');assert.equal(phoneSnapshot.phone,'544569187');
    const next={...preferences,sea_service:'lcl',container_type:null,container_count:null};
    await action(2,o.id,'destination',{destination:{...exportDestination,export_preferences:next},delivery_type:'port'});
    s=await shipment(o.id);assert.equal(s.factory_confirmed_at,null);assert.equal(s.current_quote_id,null);
    assert.deepEqual((await one('select destination_snapshot from shipping_quotes where id=$1',[quoteId])).destination_snapshot.export_preferences,preferences);
    await assert.rejects(()=>action(2,o.id,'accept',{quote_id:quoteId}),/quote|stale|invalid/);
    await action(1,o.id,'packing',{packing,ready_at:future(1)});await action(6,o.id,'quote',quote());
    s=await shipment(o.id);await action(2,o.id,'accept',{quote_id:s.current_quote_id});
    await as(1,'select mark_order_paid($1)',[o.id]);
    await assert.rejects(()=>action(2,o.id,'destination',{destination:exportDestination,delivery_type:'port'}),/locked/);
    const legacy=await order();await prepare(legacy.id);assert((await shipment(legacy.id)).current_quote_id);
  });
  console.log(`Completed ${checks} manual shipping checks; no production access.`);
} finally {await db.close();}
