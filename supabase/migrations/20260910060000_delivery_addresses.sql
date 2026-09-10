-- دفتر عناوين خاص بكل حساب؛ الحفظ والاختيار والحذف عمليات ذرّية.
-- يشغّله مالك المشروع مرة في Supabase SQL Editor، ويمكن إعادة تشغيله.
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

notify pgrst, 'reload schema';
commit;
