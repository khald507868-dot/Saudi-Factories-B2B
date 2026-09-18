-- عروض شحن يدوية لكل طلب/مصنع. الأسعار والحجز تُعتمد على الخادم فقط.
begin;
alter table public.orders add column if not exists shipping_pricing text not null default 'legacy'
  check (shipping_pricing in ('legacy','quote'));
alter table public.orders alter column shipping_pricing set default 'quote';
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in
  ('pending','awaiting_shipping','awaiting_payment','paid','processing','shipped','completed','cancelled','payment_failed'));
alter table public.private_chat_offers add column if not exists shipping_pricing text not null default 'legacy'
  check (shipping_pricing in ('legacy','quote'));
alter table public.private_chat_offers alter column shipping_pricing set default 'quote';

create table if not exists public.order_shipments (
  order_id uuid primary key references public.orders(id) on delete restrict,
  status text not null default 'awaiting_details' check(status in
    ('awaiting_details','awaiting_quote','quoted','booking_requested','booked','collected','departed','arrived','delivered','cancelled')),
  destination jsonb,
  delivery_type text check(delivery_type in ('door','port')),
  packing jsonb,
  ready_at timestamptz,
  current_quote_id uuid,
  booking_reference text,
  pickup_at timestamptz,
  revision integer not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.shipping_quotes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.order_shipments(order_id) on delete restrict,
  carrier text not null check(length(carrier) between 1 and 160),
  carrier_quote_reference text not null check(length(carrier_quote_reference) between 1 and 200),
  currency text not null default 'SAR' check(currency='SAR'),
  freight numeric(14,2) not null check(freight between 0 and 1000000000),
  additional_fees numeric(14,2) not null check(additional_fees between 0 and 1000000000),
  taxes numeric(14,2) not null check(taxes between 0 and 1000000000),
  total numeric(14,2) generated always as (freight+additional_fees+taxes) stored,
  estimated_days_min integer not null check(estimated_days_min between 1 and 365),
  estimated_days_max integer not null check(estimated_days_max between estimated_days_min and 365),
  expires_at timestamptz not null,
  inclusions text not null check(length(inclusions) between 1 and 3000),
  exclusions text not null check(length(exclusions) between 1 and 3000),
  destination_snapshot jsonb not null,
  packing_snapshot jsonb not null,
  delivery_type text not null,
  ready_at timestamptz not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique(order_id,id)
);
do $$ begin
  if not exists(select 1 from pg_constraint where conname='shipment_current_quote_fk' and conrelid='public.order_shipments'::regclass) then
    alter table public.order_shipments add constraint shipment_current_quote_fk
      foreign key(order_id,current_quote_id) references public.shipping_quotes(order_id,id);
  end if;
end $$;
create table if not exists public.shipping_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.order_shipments(order_id) on delete restrict,
  kind text not null,
  note text not null default '' check(length(note)<=3000),
  actor_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists shipping_events_order_idx on public.shipping_events(order_id,id);
create index if not exists shipping_quotes_order_idx on public.shipping_quotes(order_id,created_at);
create index if not exists order_shipments_status_idx on public.order_shipments(status,updated_at);
create table if not exists public.shipping_notifications (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid not null references public.order_shipments(order_id) on delete cascade,
  kind text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists shipping_notifications_recipient_idx on public.shipping_notifications(recipient_id,read_at,created_at);

create or replace function public.shipping_can_read(p_order_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(select 1 from public.orders o
    join public.factories f on f.id=o.factory_id where o.id=p_order_id
    and (o.buyer_id=auth.uid() or f.owner_id=auth.uid() or public.is_admin()));
$$;
alter table public.order_shipments enable row level security;
alter table public.shipping_quotes enable row level security;
alter table public.shipping_events enable row level security;
alter table public.shipping_notifications enable row level security;
revoke all on public.order_shipments,public.shipping_quotes,public.shipping_events,public.shipping_notifications from public,anon,authenticated;
grant select on public.order_shipments,public.shipping_quotes,public.shipping_events,public.shipping_notifications to authenticated;
drop policy if exists shipping_parties on public.order_shipments;
create policy shipping_parties on public.order_shipments for select to authenticated using(public.shipping_can_read(order_id));
drop policy if exists shipping_parties on public.shipping_quotes;
create policy shipping_parties on public.shipping_quotes for select to authenticated using(public.shipping_can_read(order_id));
drop policy if exists shipping_parties on public.shipping_events;
create policy shipping_parties on public.shipping_events for select to authenticated using(public.shipping_can_read(order_id));
drop policy if exists shipping_recipient on public.shipping_notifications;
create policy shipping_recipient on public.shipping_notifications for select to authenticated using(recipient_id=auth.uid());
revoke all on function public.shipping_can_read(uuid) from public,anon;
grant execute on function public.shipping_can_read(uuid) to authenticated;

create or replace function public.initialize_order_shipment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.shipping_pricing='quote' then
    if new.status <> 'awaiting_shipping' or new.shipping <> 0 then
      raise exception 'Shipping quote required' using errcode='22023';
    end if;
    insert into public.order_shipments(order_id) values(new.id);
    insert into public.shipping_notifications(recipient_id,order_id,kind)
      select f.owner_id,new.id,'packing_needed' from public.factories f where f.id=new.factory_id;
  end if;
  return new;
end $$;
revoke all on function public.initialize_order_shipment() from public,anon,authenticated;
drop trigger if exists initialize_order_shipment on public.orders;
create trigger initialize_order_shipment after insert on public.orders for each row execute function public.initialize_order_shipment();

-- مساعد داخلي: لا يقبل حقولاً فارغة أو كائنات بدلاً من النصوص.
create or replace function public.shipping_text(p_data jsonb,p_key text,p_max integer)
returns text language plpgsql immutable set search_path='' as $$
declare value text := btrim(p_data->>p_key);
begin
  if jsonb_typeof(p_data->p_key) is distinct from 'string' or value is null or length(value) not between 1 and p_max then
    raise exception 'shipping_invalid: %',p_key using errcode='22023';
  end if;
  return value;
end $$;
revoke all on function public.shipping_text(jsonb,text,integer) from public,anon,authenticated;

create or replace function public.update_manual_shipping(p_order_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare
  o public.orders%rowtype; s public.order_shipments%rowtype; q public.shipping_quotes%rowtype;
  owner uuid; admin boolean; pack jsonb; part jsonb; dest jsonb; stamp timestamptz;
  amount numeric; item_key text; event_note text := ''; next_status text;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>30000 then
    raise exception 'shipping_invalid' using errcode='22023';
  end if;
  -- ترتيب الأقفال ثابت، ويمنع الموافقة على سعر استُبدل في جلسة أخرى.
  select * into o from public.orders where id=p_order_id for update;
  select f.owner_id into owner from public.factories f where f.id=o.factory_id;
  admin := coalesce(public.is_admin(),false);
  if o.id is null or not coalesce((o.buyer_id=auth.uid() or owner=auth.uid() or admin),false) then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  select * into s from public.order_shipments where order_id=o.id for update;
  if not found or o.status in ('cancelled','payment_failed') then
    raise exception 'shipping_unavailable' using errcode='22023';
  end if;
  if p_action='accept' and o.buyer_id=auth.uid() and s.current_quote_id=(p_payload->>'quote_id')::uuid
    and exists(select 1 from public.shipping_quotes where id=s.current_quote_id and accepted_at is not null) then return s; end if;
  if p_action='book' and admin and s.status='booked' and s.booking_reference=p_payload->>'booking_reference'
    and s.pickup_at=(p_payload->>'pickup_at')::timestamptz then return s; end if;
  if (p_payload->>'revision')::integer is distinct from s.revision then
    raise exception 'shipping_stale' using errcode='22023';
  end if;

  if p_action in ('destination','packing') then
    if s.status not in ('awaiting_details','awaiting_quote','quoted') or o.status<>'awaiting_shipping' then
      raise exception 'shipping_locked' using errcode='22023';
    end if;
    if p_action='destination' then
      if auth.uid()<>o.buyer_id then raise exception 'shipping_access_denied' using errcode='42501'; end if;
      dest := p_payload->'destination';
      perform public.shipping_text(dest,'country',100),public.shipping_text(dest,'city',150),
        public.shipping_text(dest,'address',1000),public.shipping_text(dest,'contact',150),public.shipping_text(dest,'phone',60);
      if coalesce(p_payload->>'delivery_type','') not in ('door','port')
        or length(coalesce(dest->>'postal_code',''))>30 then raise exception 'shipping_invalid' using errcode='22023'; end if;
      if p_payload->>'delivery_type'='port' then perform public.shipping_text(dest,'port',200); end if;
      s.destination := dest; s.delivery_type := p_payload->>'delivery_type';
    else
      if auth.uid() is distinct from owner then raise exception 'shipping_access_denied' using errcode='42501'; end if;
      pack := p_payload->'packing';
      perform public.shipping_text(pack,'pickup_address',1500),public.shipping_text(pack,'contact',150),public.shipping_text(pack,'phone',60);
      if jsonb_typeof(pack->'packages') is distinct from 'array' then raise exception 'shipping_invalid' using errcode='22023'; end if;
      if jsonb_array_length(pack->'packages') not between 1 and 50
        or jsonb_typeof(pack->'refrigerated') is distinct from 'boolean'
        or length(coalesce(pack->>'special_requirements',''))>2000 then raise exception 'shipping_invalid' using errcode='22023'; end if;
      for part in select value from jsonb_array_elements(pack->'packages') loop
        if coalesce(part->>'type','') not in ('carton','pallet') then raise exception 'shipping_invalid' using errcode='22023'; end if;
        foreach item_key in array array['count','length_cm','width_cm','height_cm','weight_kg'] loop
          if jsonb_typeof(part->item_key) is distinct from 'number' then raise exception 'shipping_invalid' using errcode='22023'; end if;
          amount := (part->>item_key)::numeric;
          if amount<=0 or amount>100000 or (item_key='count' and amount<>trunc(amount)) then raise exception 'shipping_invalid' using errcode='22023'; end if;
        end loop;
      end loop;
      stamp := (p_payload->>'ready_at')::timestamptz;
      if stamp is null or stamp<clock_timestamp() or stamp>clock_timestamp()+interval '1 year' then raise exception 'shipping_invalid_ready_at' using errcode='22023'; end if;
      s.packing := pack; s.ready_at := stamp;
    end if;
    -- تعديل العنوان أو التغليف يبطل العرض السابق، لكنه يحتفظ بسجله.
    s.current_quote_id := null;
    s.status := case when s.destination is not null and s.packing is not null then 'awaiting_quote' else 'awaiting_details' end;
  elsif p_action='quote' then
    if not admin then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    if s.status not in ('awaiting_quote','quoted') or o.status<>'awaiting_shipping' then raise exception 'shipping_locked' using errcode='22023'; end if;
    foreach item_key in array array['freight','additional_fees','taxes'] loop
      if jsonb_typeof(p_payload->item_key) is distinct from 'number' then raise exception 'shipping_invalid' using errcode='22023'; end if;
      amount := (p_payload->>item_key)::numeric;
      if amount<0 or amount>1000000000 or amount<>round(amount,2) then raise exception 'shipping_invalid' using errcode='22023'; end if;
    end loop;
    stamp := (p_payload->>'expires_at')::timestamptz;
    if stamp is null or stamp<=clock_timestamp() or stamp>clock_timestamp()+interval '90 days' then raise exception 'shipping_invalid_expiry' using errcode='22023'; end if;
    insert into public.shipping_quotes(order_id,carrier,carrier_quote_reference,freight,additional_fees,taxes,
      estimated_days_min,estimated_days_max,expires_at,inclusions,exclusions,destination_snapshot,packing_snapshot,delivery_type,ready_at,created_by)
    values(o.id,public.shipping_text(p_payload,'carrier',160),public.shipping_text(p_payload,'carrier_quote_reference',200),
      (p_payload->>'freight')::numeric,(p_payload->>'additional_fees')::numeric,(p_payload->>'taxes')::numeric,
      (p_payload->>'estimated_days_min')::integer,(p_payload->>'estimated_days_max')::integer,stamp,
      public.shipping_text(p_payload,'inclusions',3000),public.shipping_text(p_payload,'exclusions',3000),s.destination,s.packing,s.delivery_type,s.ready_at,auth.uid()) returning * into q;
    s.current_quote_id := q.id; s.status := 'quoted';
  elsif p_action in ('accept','decline') then
    if o.buyer_id<>auth.uid() then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    if s.status<>'quoted' or o.status<>'awaiting_shipping' or s.current_quote_id is distinct from (p_payload->>'quote_id')::uuid then
      raise exception 'shipping_stale' using errcode='22023'; end if;
    select * into q from public.shipping_quotes where id=s.current_quote_id for update;
    if p_action='accept' then
      if q.expires_at<=clock_timestamp() then raise exception 'shipping_quote_expired' using errcode='22023'; end if;
      -- رسوم المنصة وضريبة المنتجات تبقيان كما ثُبتتا. ضرائب الشحن داخل عرض الشركة، ولا تتكرر.
      update public.orders set shipping=q.total,total=subtotal+payment_fee+vat_amount+q.total,
        status='awaiting_payment',updated_at=clock_timestamp() where id=o.id;
      update public.shipping_quotes set accepted_at=clock_timestamp() where id=q.id;
      s.status := 'booking_requested';
    else
      s.current_quote_id := null; s.status := 'awaiting_quote';
    end if;
  elsif p_action='book' then
    if not admin then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    if s.status<>'booking_requested' then raise exception 'shipping_locked' using errcode='22023'; end if;
    stamp := (p_payload->>'pickup_at')::timestamptz;
    if stamp is null or stamp<s.ready_at or stamp<clock_timestamp() or stamp>clock_timestamp()+interval '1 year' then
      raise exception 'shipping_invalid_pickup' using errcode='22023'; end if;
    s.booking_reference := public.shipping_text(p_payload,'booking_reference',200);
    s.pickup_at := stamp; s.status := 'booked';
  elsif p_action='track' then
    if not admin then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    next_status := case s.status when 'booked' then 'collected' when 'collected' then 'departed'
      when 'departed' then 'arrived' when 'arrived' then 'delivered' end;
    if next_status is null or next_status is distinct from p_payload->>'status'
      or s.pickup_at>clock_timestamp() then raise exception 'shipping_invalid_transition' using errcode='22023'; end if;
    event_note := public.shipping_text(p_payload,'note',3000);
    s.status := next_status;
  elsif p_action='cancel' then
    if o.buyer_id<>auth.uid() and not admin then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    if o.status<>'awaiting_shipping' then raise exception 'shipping_locked' using errcode='22023'; end if;
    s.status := 'cancelled';
    update public.orders set status='cancelled',updated_at=clock_timestamp() where id=o.id;
  else
    raise exception 'shipping_invalid_action' using errcode='22023';
  end if;
  update public.order_shipments set status=s.status,destination=s.destination,delivery_type=s.delivery_type,
    packing=s.packing,ready_at=s.ready_at,current_quote_id=s.current_quote_id,booking_reference=s.booking_reference,
    pickup_at=s.pickup_at,revision=revision+1,updated_at=clock_timestamp() where order_id=o.id returning * into s;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,
    case when p_action='track' then s.status else p_action end,event_note,auth.uid());
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,case when p_action='track' then s.status else p_action end from public.profiles
    where (id=o.buyer_id or id=owner or is_admin=true) and id<>auth.uid();
  return s;
end $$;
revoke all on function public.update_manual_shipping(uuid,text,jsonb) from public,anon;
grant execute on function public.update_manual_shipping(uuid,text,jsonb) to authenticated;

create or replace function public.read_shipping_notifications(p_order_id uuid,p_through_id bigint)
returns void language sql security definer set search_path='' as $$
  update public.shipping_notifications set read_at=clock_timestamp()
  where recipient_id=auth.uid() and order_id=p_order_id and id<=p_through_id and read_at is null;
$$;
revoke all on function public.read_shipping_notifications(uuid,bigint) from public,anon;
grant execute on function public.read_shipping_notifications(uuid,bigint) to authenticated;

-- تُضاف هنا تعريفات الشراء بعد تحديثها؛ لا تُغيّر الهجرات التاريخية.

create or replace function public.create_order_from_cart(
  p_factory_id bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns public.orders
language plpgsql security definer set search_path = ''
as $fn$
declare
  cart_row public.carts%rowtype;
  result_row public.orders%rowtype;
  item record;
  items jsonb := '[]'::jsonb;
  price_value numeric;
  line_value numeric;
  subtotal_value numeric := 0;
  shipping_value numeric := 0;
  fee_value numeric;
  vat_value numeric;
  total_value numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_factory_id is null or p_idempotency_key is null then
    raise exception 'Factory and request key are required' using errcode = '22023';
  end if;

  -- قفل السلة يسلسل طلبات المشتري؛ إعادة المحاولة لا تعدّل طلباً سابقاً.
  select * into cart_row from public.carts where owner_id = auth.uid() for update;
  if not found then raise exception 'Cart is empty' using errcode = '22023'; end if;
  select * into result_row from public.orders
    where buyer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if found then
    if result_row.factory_id <> p_factory_id then
      raise exception 'Request key belongs to another factory' using errcode = '22023';
    end if;
    return result_row;
  end if;

  perform 1 from public.factories where id = p_factory_id and status = 'approved' for share;
  if not found then raise exception 'Factory unavailable' using errcode = '22023'; end if;

  -- تُلتقط الأسعار والكميات مرة واحدة، وتُقفل الصفوف الموجودة حتى اكتمال الطلب.
  for item in
    select ci.id as cart_item_id, ci.product_id, ci.quantity, p.factory_id, p.name,
      coalesce(cp.price, public.tier_unit_price(p.id, ci.quantity), p.price) as unit_price
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp on cp.product_id = p.id
      and cp.factory_id = p.factory_id and cp.customer_id = auth.uid()
    where ci.cart_id = cart_row.id and p.factory_id = p_factory_id
    order by ci.id
    for update of ci for share of p
  loop
    price_value := item.unit_price;
    if price_value is null or price_value < 0 or price_value >= 1000000000000
      or item.quantity is null or item.quantity <= 0 or item.quantity >= 1000000000 then
      raise exception 'Cart contains unavailable or unpriced products' using errcode = '22023';
    end if;
    price_value := round(price_value, 2);
    line_value := round(price_value * item.quantity, 2);
    subtotal_value := subtotal_value + line_value;
    items := items || jsonb_build_array(jsonb_build_object(
      'cart_item_id', item.cart_item_id, 'product_id', item.product_id,
      'product_name', item.name, 'unit_price', price_value,
      'quantity', item.quantity, 'line_total', line_value
    ));
  end loop;
  if jsonb_array_length(items) = 0 then
    raise exception 'Cart has no products for this factory' using errcode = '22023';
  end if;
  fee_value := round((subtotal_value + shipping_value) * 0.01, 2);
  vat_value := round((subtotal_value + shipping_value + fee_value) * 0.15, 2);
  total_value := subtotal_value + shipping_value + fee_value + vat_value;
  if total_value >= 1000000000000 then
    raise exception 'Order total is invalid' using errcode = '22023';
  end if;

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, shipping, payment_fee,
    vat_rate, vat_amount, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_shipping', subtotal_value, shipping_value,
    fee_value, 0.15, vat_value, total_value, p_idempotency_key
  ) returning * into result_row;
  insert into public.order_items(order_id, product_id, product_name, unit_price, quantity, line_total)
    select result_row.id, x.product_id, x.product_name, x.unit_price, x.quantity, x.line_total
    from jsonb_to_recordset(items) as x(product_id bigint, product_name text,
      unit_price numeric, quantity numeric, line_total numeric);
  -- لا تُحذف إضافات متزامنة لم تدخل في لقطة الطلب.
  delete from public.cart_items where cart_id = cart_row.id
    and id in (select (x->>'cart_item_id')::bigint from jsonb_array_elements(items) x);
  return result_row;
end;
$fn$;
revoke all on function public.create_order_from_cart(bigint,uuid) from public, anon;
grant execute on function public.create_order_from_cart(bigint,uuid) to authenticated;

create or replace function public.create_private_chat_offer(
  p_conversation_id bigint, p_product_id bigint, p_quantity integer,
  p_unit_price numeric, p_valid_days integer, p_notes text, p_request_key uuid
) returns public.private_chat_offers language plpgsql security definer set search_path = '' as $$
declare
  c public.conversations%rowtype;
  f public.factories%rowtype;
  p public.products%rowtype;
  q public.private_chat_offers%rowtype;
  mid bigint;
  sub numeric(14,2); fee numeric(14,2); vat numeric(14,2);
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity not between 1 and 100000
    or p_unit_price is null or p_unit_price <= 0 or p_unit_price > 1000000
    or p_unit_price <> round(p_unit_price,2) or p_valid_days is null or p_valid_days not between 1 and 30
    or p_request_key is null or length(coalesce(p_notes,'')) > 1000 then
    raise exception 'offer_invalid' using errcode = '22023';
  end if;
  select * into c from public.conversations where id = p_conversation_id;
  select * into f from public.factories where id = c.factory_id for share;
  if c.id is null or f.owner_id is distinct from auth.uid() or f.status <> 'approved'
    or c.individual_id = auth.uid() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  -- Serialize retries of the same draft, including two simultaneous requests.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_key::text, 0));
  select * into q from public.private_chat_offers where seller_id = auth.uid() and request_key = p_request_key;
  if found then
    if q.conversation_id <> p_conversation_id or q.product_id is distinct from p_product_id
      or q.quantity <> p_quantity or q.unit_price <> p_unit_price or q.valid_days <> p_valid_days
      or q.notes <> btrim(coalesce(p_notes,'')) then
      raise exception 'offer_invalid' using errcode = '22023';
    end if;
    return q;
  end if;
  select * into p from public.products where id = p_product_id and factory_id = f.id for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  sub := p_quantity * p_unit_price;
  -- الشحن يُسعّر لاحقاً بعرض مستقل؛ هذه مبالغ المنتجات فقط.
  fee := round((sub) * 0.01, 2);
  vat := round((sub + fee) * 0.15, 2);
  insert into public.messages(conversation_id, sender_id, body)
    values(c.id, auth.uid(), 'عرض سعر خاص / Private offer: ' || left(p.name, 200)) returning id into mid;
  insert into public.private_chat_offers(
    conversation_id, message_id, factory_id, seller_id, buyer_id, product_id, product_name, product_image,
    quantity, unit_price, subtotal, shipping, payment_fee, vat_rate, vat_amount, total,
    valid_days, expires_at, notes, request_key
  ) values (
    c.id, mid, f.id, auth.uid(), c.individual_id, p.id, p.name,
    coalesce(nullif(p.images[1],''), p.image, ''),
    p_quantity, p_unit_price, sub, 0, fee, 0.15, vat, sub + fee + vat,
    p_valid_days, clock_timestamp() + make_interval(days => p_valid_days), btrim(coalesce(p_notes,'')), p_request_key
  ) returning * into q;
  return q;
end;
$$;
create or replace function public.accept_private_chat_offer(p_offer_id uuid)
returns public.private_chat_offers language plpgsql security definer set search_path = '' as $$
declare q public.private_chat_offers%rowtype; oid uuid;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  select * into q from public.private_chat_offers where id = p_offer_id and buyer_id = auth.uid() for update;
  if not found then raise exception 'offer_access_denied' using errcode = '42501'; end if;
  -- One offer creates at most one order, even after a timeout or double click.
  if q.status = 'accepted' then return q; end if;
  if q.status <> 'pending' or q.expires_at <= clock_timestamp() then
    raise exception 'offer_unavailable' using errcode = '22023';
  end if;
  if q.shipping_pricing <> 'quote' then
    raise exception 'offer_shipping_reissue_required' using errcode='22023';
  end if;
  perform 1 from public.factories where id = q.factory_id and owner_id = q.seller_id and status = 'approved' for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  perform 1 from public.products where id = q.product_id and factory_id = q.factory_id for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  insert into public.orders(buyer_id, factory_id, status, currency, subtotal, shipping, payment_fee, vat_rate, vat_amount, total)
    values(q.buyer_id, q.factory_id, 'awaiting_shipping', q.currency, q.subtotal, q.shipping, q.payment_fee, q.vat_rate, q.vat_amount, q.total)
    returning id into oid;
  insert into public.order_items(order_id, product_id, product_name, unit_price, quantity, line_total)
    values(oid, q.product_id, q.product_name, q.unit_price, q.quantity, q.subtotal);
  update public.private_chat_offers set status = 'accepted', order_id = oid, updated_at = clock_timestamp()
    where id = q.id returning * into q;
  return q;
end;
$$;
notify pgrst, 'reload schema';
commit;
