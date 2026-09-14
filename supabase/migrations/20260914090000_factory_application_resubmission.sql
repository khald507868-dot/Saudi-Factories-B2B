begin;

-- A confirmed owner may correct registration fields and return only their
-- rejected application to pending. No approval or general write access.
create or replace function public.is_factory_resubmission(old_row jsonb, new_row jsonb)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    old_row->>'status' = 'rejected' and new_row->>'status' = 'pending'
    and old_row->>'owner_id' = auth.uid()::text
    and new_row->>'rejection_reason' = ''
    and exists (select 1 from auth.users u join public.profiles p on p.id = u.id
      where u.id = auth.uid() and u.email_confirmed_at is not null and p.account_type = 'factory')
    and old_row - array['status','rejection_reason','updated_at','name','commercial_register',
      'industrial_license','address_city','address_district','address_short','address_building',
      'address_secondary','address_postal','address_street']
      = new_row - array['status','rejection_reason','updated_at','name','commercial_register',
      'industrial_license','address_city','address_district','address_short','address_building',
      'address_secondary','address_postal','address_street']
    and length(btrim(new_row->>'name')) between 1 and 200
    and new_row->>'commercial_register' ~ '^[0-9]{1,10}$'
    and new_row->>'industrial_license' ~ '^[0-9]{1,10}$'
    and not exists (select 1 from jsonb_each(new_row) x
      where x.key = any(array['name','commercial_register','industrial_license','address_city',
        'address_district','address_short','address_building','address_secondary','address_postal','address_street'])
      and (jsonb_typeof(x.value) <> 'string' or length(x.value #>> '{}') > 200)), false);
$$;
revoke all on function public.is_factory_resubmission(jsonb,jsonb) from public, anon, authenticated;

create or replace function public.require_approved_account_write()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_schema = 'public' and tg_table_name = 'factories' and tg_op = 'UPDATE' then
    if public.is_factory_resubmission(to_jsonb(old), to_jsonb(new)) then return new; end if;
  end if;
  if auth.uid() is not null and coalesce(auth.role(), '') <> 'service_role'
     and not public.account_can_write() then
    raise exception 'Email confirmation and factory approval are required' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.guard_factory_columns()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if public.is_factory_resubmission(to_jsonb(old), to_jsonb(new)) then return new; end if;
  if not public.is_admin() then
    new.status := old.status;
    new.rejection_reason := old.rejection_reason;
  end if;
  new.owner_id := old.owner_id;
  return new;
end;
$$;

create or replace function public.resubmit_factory_application(details jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  application public.factories%rowtype;
  corrected public.factories%rowtype;
begin
  if not exists (select 1 from auth.users u join public.profiles p on p.id = u.id
    where u.id = auth.uid() and u.email_confirmed_at is not null and p.account_type = 'factory') then
    raise exception 'application_unavailable' using errcode = '42501';
  end if;
  if details is null or jsonb_typeof(details) <> 'object' then
    raise exception 'invalid_application_details' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(details) k where k <> all(array[
    'name','commercial_register','industrial_license','address_city','address_district',
    'address_short','address_building','address_secondary','address_postal','address_street'])) then
    raise exception 'invalid_application_details' using errcode = '22023';
  end if;
  select * into application from public.factories where owner_id = auth.uid() for update;
  if not found or application.status <> 'rejected' then
    raise exception 'application_not_rejected' using errcode = '42501';
  end if;
  -- Keep existing optional fields when omitted; normalize old nullable addresses.
  select * into corrected from jsonb_populate_record(application, details);
  corrected.address_city := coalesce(corrected.address_city, '');
  corrected.address_district := coalesce(corrected.address_district, '');
  corrected.address_short := coalesce(corrected.address_short, '');
  corrected.address_building := coalesce(corrected.address_building, '');
  corrected.address_secondary := coalesce(corrected.address_secondary, '');
  corrected.address_postal := coalesce(corrected.address_postal, '');
  corrected.address_street := coalesce(corrected.address_street, '');
  corrected.status := 'pending';
  corrected.rejection_reason := '';
  if not public.is_factory_resubmission(to_jsonb(application), to_jsonb(corrected)) then
    raise exception 'invalid_application_details' using errcode = '22023';
  end if;
  update public.factories set
    name = btrim(corrected.name), commercial_register = corrected.commercial_register,
    industrial_license = corrected.industrial_license,
    address_city = corrected.address_city, address_district = corrected.address_district,
    address_short = corrected.address_short, address_building = corrected.address_building,
    address_secondary = corrected.address_secondary, address_postal = corrected.address_postal,
    address_street = corrected.address_street, status = 'pending', rejection_reason = '', updated_at = now()
    where id = application.id;
  return jsonb_build_object('status', 'pending');
end;
$$;
revoke all on function public.resubmit_factory_application(jsonb) from public, anon;
grant execute on function public.resubmit_factory_application(jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
