-- موافقات متتابعة: المشتري، المصنع، عرض الشركة، موافقة المشتري والدفع.
-- الإدارة تسجّل عرض الشركة مؤقتاً. الدفع اليدوي الحالي يظل مع إثبات استلامه.
begin;
-- تهيئة الموافقات التاريخية مرة واحدة، دون إعادة اعتماد شحنة معدلة عند تكرار الترحيل.
do $$ begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='order_shipments' and column_name='buyer_confirmed_at') then
    alter table public.order_shipments add column buyer_confirmed_at timestamptz, add column factory_confirmed_at timestamptz;
    update public.order_shipments set buyer_confirmed_at=case when destination is not null then updated_at end,
      factory_confirmed_at=case when destination is not null and packing is not null then updated_at end;
  end if;
end $$;

create or replace function public.initialize_order_shipment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.shipping_pricing='quote' then
    if new.status <> 'awaiting_shipping' or new.shipping <> 0 then
      raise exception 'Shipping quote required' using errcode='22023';
    end if;
    insert into public.order_shipments(order_id) values(new.id);
    insert into public.shipping_notifications(recipient_id,order_id,kind)
      values(new.buyer_id,new.id,'buyer_details_needed');
  end if;
  return new;
end $$;
revoke all on function public.initialize_order_shipment() from public,anon,authenticated;
drop trigger if exists initialize_order_shipment on public.orders;
create trigger initialize_order_shipment after insert on public.orders for each row execute function public.initialize_order_shipment();

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
      if s.destination=dest and s.delivery_type=p_payload->>'delivery_type' and s.buyer_confirmed_at is not null then return s; end if;
      s.destination := dest; s.delivery_type := p_payload->>'delivery_type';
      s.buyer_confirmed_at := clock_timestamp(); s.factory_confirmed_at := null;
    else
      if auth.uid() is distinct from owner then raise exception 'shipping_access_denied' using errcode='42501'; end if;
      if s.buyer_confirmed_at is null or s.destination is null then
        raise exception 'shipping_buyer_confirmation_required' using errcode='22023';
      end if;
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
      s.factory_confirmed_at := clock_timestamp();
    end if;
    -- تعديل العنوان أو التغليف يبطل العرض السابق، لكنه يحتفظ بسجله.
    s.current_quote_id := null;
    s.status := case when s.buyer_confirmed_at is not null and s.factory_confirmed_at is not null then 'awaiting_quote' else 'awaiting_details' end;
  elsif p_action='quote' then
    if not admin then raise exception 'shipping_access_denied' using errcode='42501'; end if;
    if s.buyer_confirmed_at is null or s.factory_confirmed_at is null then
      raise exception 'shipping_factory_confirmation_required' using errcode='22023';
    end if;
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
    if o.status not in ('paid','processing','shipped','completed') then
      raise exception 'shipping_payment_required' using errcode='22023';
    end if;
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
    buyer_confirmed_at=s.buyer_confirmed_at,factory_confirmed_at=s.factory_confirmed_at,
    pickup_at=s.pickup_at,revision=revision+1,updated_at=clock_timestamp() where order_id=o.id returning * into s;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,
    case when p_action='track' then s.status else p_action end,event_note,auth.uid());
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,case when p_action='track' then s.status else p_action end from public.profiles
    where (case when p_action='destination' then id=owner
      when p_action='packing' then is_admin=true
      when p_action='quote' then id=o.buyer_id
      else (id=o.buyer_id or id=owner or is_admin=true) end) and id<>auth.uid();
  return s;
end $$;
revoke all on function public.update_manual_shipping(uuid,text,jsonb) from public,anon;
grant execute on function public.update_manual_shipping(uuid,text,jsonb) to authenticated;

create or replace function public.set_domestic_shipping_destination(
  p_order_id uuid,p_revision integer,p_expected_destination jsonb
)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; s public.order_shipments%rowtype; dest jsonb; owner uuid;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  select * into o from public.orders where id=p_order_id and buyer_id=auth.uid() for update;
  if not found then raise exception 'shipping_access_denied' using errcode='42501'; end if;
  select * into s from public.order_shipments where order_id=o.id for update;
  if not found or o.status<>'awaiting_shipping' or s.status not in ('awaiting_details','awaiting_quote','quoted') then
    raise exception 'shipping_locked' using errcode='22023';
  end if;
  if p_revision is distinct from s.revision then raise exception 'shipping_stale' using errcode='22023'; end if;
  dest := public.get_domestic_shipping_destination(o.id);
  if dest is null then raise exception 'shipping_saved_address_missing' using errcode='22023'; end if;
  -- لا تُقبل بيانات بديلة من المتصفح. تغيير العنوان في جلسة أخرى يوجب مراجعته.
  if p_expected_destination is distinct from dest then raise exception 'shipping_stale' using errcode='22023'; end if;
  perform public.shipping_text(dest,'address',1000),public.shipping_text(dest,'contact',150),public.shipping_text(dest,'phone',60);
  -- إعادة الطلب نفسه لا تبطل عرضاً جديداً وصل بعد الحفظ السابق.
  if s.destination=dest and s.delivery_type='door' and s.buyer_confirmed_at is not null then return s; end if;
  update public.order_shipments set destination=dest,delivery_type='door',current_quote_id=null,
    status='awaiting_details',buyer_confirmed_at=clock_timestamp(),factory_confirmed_at=null,
    revision=revision+1,updated_at=clock_timestamp() where order_id=o.id returning * into s;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,'destination','',auth.uid());
  select owner_id into owner from public.factories where id=o.factory_id;
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,'destination' from public.profiles where id=owner and id<>auth.uid();
  return s;
end $$;
revoke all on function public.set_domestic_shipping_destination(uuid,integer,jsonb) from public,anon;
grant execute on function public.set_domestic_shipping_destination(uuid,integer,jsonb) to authenticated;
create or replace function public.mark_order_paid(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_order public.orders;
begin
  -- صاحب المصنع وحده، أو المدير. المشتري لا يعلّم طلبه مدفوعاً
  -- بنفسه: المال يصل إلى المصنع، فهو الذي يشهد بوصوله.
  select o.* into v_order
    from public.orders o
    join public.factories f on f.id = o.factory_id
   where o.id = p_order_id
     and (f.owner_id = auth.uid() or public.is_admin())
   for update;

  if not found then
    raise exception 'Order access denied'
      using errcode = '42501';
  end if;

  -- الانتقال المسموح واحد فقط. ومنه يُمنع تعليم طلب ملغى
  -- أو فاشل الدفع مدفوعاً، ويُمنع إرجاع طلب شُحن أو اكتمل.
  if v_order.status not in ('pending', 'awaiting_payment') then
    raise exception 'Order is not awaiting payment (status: %)', v_order.status
      using errcode = '22023';
  end if;

  update public.orders
     set status = 'paid',
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  if exists(select 1 from public.order_shipments where order_id=v_order.id) then
    insert into public.shipping_events(order_id,kind,note,actor_id) values(v_order.id,'payment','',auth.uid());
    insert into public.shipping_notifications(recipient_id,order_id,kind)
      select id,v_order.id,'payment' from public.profiles where (id=v_order.buyer_id or is_admin=true) and id<>auth.uid();
  end if;
  return v_order;
end;
$fn$;


revoke all on function public.mark_order_paid(uuid) from public,anon;
grant execute on function public.mark_order_paid(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
