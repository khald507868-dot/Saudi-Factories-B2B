-- اختيار الشحن المحلي مع تجهيز دفتر العناوين عند غياب هجرته السابقة.
-- الملف كامل وقابل لإعادة التشغيل، ولا يحذف عناوين أو طلبات موجودة.
begin;
create table if not exists public.delivery_addresses (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 60),
  address_line text not null check (char_length(btrim(address_line)) between 1 and 500),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  building text not null default '' check (char_length(building) <= 80),
  floor text not null default '' check (char_length(floor) <= 40),
  apartment text not null default '' check (char_length(apartment) <= 40),
  notes text not null default '' check (char_length(notes) <= 500),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create unique index if not exists delivery_addresses_one_default
  on public.delivery_addresses (user_id) where is_default;
create index if not exists delivery_addresses_list
  on public.delivery_addresses (user_id, created_at, id);

alter table public.delivery_addresses enable row level security;
revoke all on public.delivery_addresses from public, anon, authenticated;
grant select on public.delivery_addresses to authenticated;

drop policy if exists delivery_addresses_read_own on public.delivery_addresses;
create policy delivery_addresses_read_own on public.delivery_addresses
  for select to authenticated using (user_id = (select auth.uid()));
-- يحفظ العزل حتى إن أُضيفت لاحقاً سياسة قراءة أوسع بالخطأ.
drop policy if exists delivery_addresses_owner_guard on public.delivery_addresses;
create policy delivery_addresses_owner_guard on public.delivery_addresses
  as restrictive for all to public
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.save_delivery_address(
  p_expected_user_id uuid,
  p_address jsonb
) returns setof public.delivery_addresses
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_lat double precision;
  v_lon double precision;
begin
  if v_uid is null or p_expected_user_id is distinct from v_uid then
    raise exception 'delivery_session_changed' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery-addresses:' || v_uid::text, 0)
  );
  if p_address is null or pg_catalog.jsonb_typeof(p_address) <> 'object' then
    raise exception 'delivery_invalid_address' using errcode = '22023';
  end if;
  begin
    v_id := (p_address->>'id')::uuid;
    v_lat := (p_address->>'latitude')::double precision;
    v_lon := (p_address->>'longitude')::double precision;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'delivery_invalid_address' using errcode = '22023';
  end;
  if v_id is null then
    raise exception 'delivery_invalid_address' using errcode = '22023';
  end if;
  if v_lat is null or v_lon is null or not (v_lat between -90 and 90)
    or not (v_lon between -180 and 180) then
    raise exception 'delivery_invalid_location' using errcode = '22023';
  end if;
  if not exists (select 1 from public.delivery_addresses where user_id = v_uid and id = v_id)
    and (select count(*) from public.delivery_addresses where user_id = v_uid) >= 20 then
    raise exception 'delivery_address_limit' using errcode = '22023';
  end if;
  update public.delivery_addresses set is_default = false, updated_at = now()
    where user_id = v_uid and is_default;
  begin
    insert into public.delivery_addresses (
      id, user_id, label, address_line, latitude, longitude,
      building, floor, apartment, notes, is_default
    ) values (
      v_id, v_uid, btrim(p_address->>'label'), btrim(p_address->>'address_line'), v_lat, v_lon,
      btrim(coalesce(p_address->>'building', '')), btrim(coalesce(p_address->>'floor', '')),
      btrim(coalesce(p_address->>'apartment', '')), btrim(coalesce(p_address->>'notes', '')), true
    ) on conflict (user_id, id) do update set
      label = excluded.label, address_line = excluded.address_line,
      latitude = excluded.latitude, longitude = excluded.longitude,
      building = excluded.building, floor = excluded.floor, apartment = excluded.apartment,
      notes = excluded.notes, is_default = true, updated_at = now();
  exception when check_violation or not_null_violation then
    raise exception 'delivery_invalid_address' using errcode = '22023';
  end;
  return query select d.* from public.delivery_addresses d
    where d.user_id = v_uid order by d.created_at, d.id;
end;
$$;

create or replace function public.select_delivery_address(
  p_expected_user_id uuid,
  p_id uuid
) returns setof public.delivery_addresses
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or p_expected_user_id is distinct from v_uid then
    raise exception 'delivery_session_changed' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery-addresses:' || v_uid::text, 0)
  );
  if not exists (select 1 from public.delivery_addresses where user_id = v_uid and id = p_id) then
    raise exception 'delivery_address_missing' using errcode = '22023';
  end if;
  update public.delivery_addresses set is_default = false, updated_at = now()
    where user_id = v_uid and is_default and id <> p_id;
  update public.delivery_addresses set is_default = true, updated_at = now()
    where user_id = v_uid and id = p_id;
  return query select d.* from public.delivery_addresses d
    where d.user_id = v_uid order by d.created_at, d.id;
end;
$$;

create or replace function public.delete_delivery_address(
  p_expected_user_id uuid,
  p_id uuid
) returns setof public.delivery_addresses
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_default boolean;
begin
  if v_uid is null or p_expected_user_id is distinct from v_uid then
    raise exception 'delivery_session_changed' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery-addresses:' || v_uid::text, 0)
  );
  delete from public.delivery_addresses where user_id = v_uid and id = p_id
    returning is_default into v_default;
  if not found then
    raise exception 'delivery_address_missing' using errcode = '22023';
  end if;
  if v_default then
    update public.delivery_addresses set is_default = true, updated_at = now()
      where user_id = v_uid and id = (
        select id from public.delivery_addresses where user_id = v_uid
        order by created_at, id limit 1
      );
  end if;
  return query select d.* from public.delivery_addresses d
    where d.user_id = v_uid order by d.created_at, d.id;
end;
$$;

revoke all on function public.save_delivery_address(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.select_delivery_address(uuid, uuid) from public, anon, authenticated;
revoke all on function public.delete_delivery_address(uuid, uuid) from public, anon, authenticated;
grant execute on function public.save_delivery_address(uuid, jsonb) to authenticated;
grant execute on function public.select_delivery_address(uuid, uuid) to authenticated;
grant execute on function public.delete_delivery_address(uuid, uuid) to authenticated;

-- إضافة حارس اعتماد الحساب للجدول المنشأ حديثاً أيضاً.
drop trigger if exists account_approval_write_guard on public.delivery_addresses;
create trigger account_approval_write_guard before insert or update or delete on public.delivery_addresses
  for each row execute function public.require_approved_account_write();

create or replace function public.shipping_is_saudi_country(p_country text)
returns boolean language sql immutable set search_path='' as $$
  select lower(regexp_replace(btrim(coalesce(p_country,'')),'\s+',' ','g')) = any(array[
    'sa','sau','ksa','saudi arabia','kingdom of saudi arabia',
    'السعودية','السعوديه','المملكة العربية السعودية','المملكه العربيه السعوديه']);
$$;
revoke all on function public.shipping_is_saudi_country(text) from public,anon,authenticated;

create or replace function public.get_domestic_shipping_destination(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  dest jsonb;
  saved public.delivery_addresses%rowtype;
  profile public.profiles%rowtype;
begin
  if auth.uid() is null or not exists(select 1 from public.orders where id=p_order_id and buyer_id=auth.uid()) then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  -- عنوان الطلب الحالي أولاً، حتى لا يتغير المستلم عند إعادة فتحه.
  select s.destination into dest from public.order_shipments s where s.order_id=p_order_id
    and public.shipping_is_saudi_country(s.destination->>'country');
  if dest is not null then
    return (dest - 'port') || jsonb_build_object('scope','domestic','country','Saudi Arabia');
  end if;
  select * into saved from public.delivery_addresses where user_id=auth.uid() and is_default;
  if found then
    select * into profile from public.profiles where id=auth.uid();
    if length(btrim(coalesce(profile.full_name,'')))=0 or length(btrim(coalesce(profile.phone,'')))=0 then
      raise exception 'shipping_contact_missing' using errcode='22023';
    end if;
    return jsonb_build_object('scope','domestic','country','Saudi Arabia',
      'address',concat_ws(' · ',saved.address_line,nullif(saved.building,''),nullif(saved.floor,''),nullif(saved.apartment,'')),
      'contact',profile.full_name,'phone',profile.phone,'phone_country_code',profile.country_code,
      'latitude',saved.latitude,'longitude',saved.longitude,'delivery_notes',saved.notes,
      'saved_address_id',saved.id);
  end if;
  -- حسابات الموقع قد تحفظ العنوان في طلب سابق دون دفتر عناوين التطبيق.
  select s.destination into dest from public.order_shipments s join public.orders o on o.id=s.order_id
    where o.buyer_id=auth.uid() and s.order_id<>p_order_id
      and public.shipping_is_saudi_country(s.destination->>'country')
    order by s.updated_at desc,s.order_id limit 1;
  if dest is null then return null; end if;
  return (dest - 'port') || jsonb_build_object('scope','domestic','country','Saudi Arabia');
end $$;
revoke all on function public.get_domestic_shipping_destination(uuid) from public,anon;
grant execute on function public.get_domestic_shipping_destination(uuid) to authenticated;

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
  if s.destination=dest and s.delivery_type='door' then return s; end if;
  update public.order_shipments set destination=dest,delivery_type='door',current_quote_id=null,
    status=case when packing is null then 'awaiting_details' else 'awaiting_quote' end,
    revision=revision+1,updated_at=clock_timestamp() where order_id=o.id returning * into s;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,'destination','',auth.uid());
  select owner_id into owner from public.factories where id=o.factory_id;
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,'destination' from public.profiles where (id=owner or is_admin=true) and id<>auth.uid();
  return s;
end $$;
revoke all on function public.set_domestic_shipping_destination(uuid,integer,jsonb) from public,anon;
grant execute on function public.set_domestic_shipping_destination(uuid,integer,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
