-- بعد ترحيل الشحن المحلي: فصل أجزاء العنوان مع استمرار دعم التطبيق القديم.
begin;
alter table public.delivery_addresses
  add column if not exists address_scope text,
  add column if not exists country text not null default '',
  add column if not exists city text not null default '',
  add column if not exists district text not null default '',
  add column if not exists street text not null default '',
  add column if not exists short_address text not null default '',
  add column if not exists postal_code text not null default '',
  add column if not exists additional_number text not null default '';

-- إذا عدّل عميل قديم النص أو النقطة، لا تبقى أجزاء عنوان قديم مرتبطة بمكان جديد.
create or replace function public.clear_legacy_address_parts()
returns trigger language plpgsql set search_path='' as $$
begin
  if (new.address_line,new.latitude,new.longitude) is distinct from (old.address_line,old.latitude,old.longitude) then
    new.address_scope:='legacy_review'; new.country:=''; new.city:=''; new.district:=''; new.street:='';
    new.short_address:=''; new.postal_code:=''; new.additional_number:='';
  end if;
  return new;
end $$;
revoke all on function public.clear_legacy_address_parts() from public,anon,authenticated;
drop trigger if exists clear_legacy_address_parts on public.delivery_addresses;
create trigger clear_legacy_address_parts before update on public.delivery_addresses
  for each row execute function public.clear_legacy_address_parts();

create or replace function public.save_structured_delivery_address(p_expected_user_id uuid,p_address jsonb)
returns setof public.delivery_addresses language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_scope text; v_country text; v_city text; v_district text; v_street text;
  v_short text; v_postal text; v_additional text; v_building text; v_line text; v_key text; v_id uuid;
begin
  if v_uid is null or v_uid is distinct from p_expected_user_id or not public.account_can_write() then
    raise exception 'delivery_session_changed' using errcode='42501';
  end if;
  if p_address is null or jsonb_typeof(p_address)<>'object' then
    raise exception 'delivery_invalid_address' using errcode='22023';
  end if;
  foreach v_key in array array['address_scope','country','city','district','street','short_address','postal_code','additional_number','building'] loop
    if p_address ? v_key and jsonb_typeof(p_address->v_key)<>'string' then
      raise exception 'delivery_invalid_address' using errcode='22023';
    end if;
  end loop;
  v_scope:=p_address->>'address_scope';
  v_country:=btrim(coalesce(p_address->>'country',''));
  v_city:=btrim(coalesce(p_address->>'city',''));
  v_district:=btrim(coalesce(p_address->>'district',''));
  if v_scope is null or v_scope not in ('domestic','international')
    or length(v_country) not between 1 and 100 or length(v_city) not between 1 and 100 or length(v_district)>100 then
    raise exception 'delivery_invalid_address' using errcode='22023';
  end if;
  if (v_scope='domestic') is distinct from public.shipping_is_saudi_country(v_country) then
    raise exception 'delivery_country_scope_mismatch' using errcode='22023';
  end if;
  if v_scope='domestic' then
    v_country:='Saudi Arabia';
    v_street:=btrim(coalesce(p_address->>'street',''));
    v_short:=upper(translate(btrim(coalesce(p_address->>'short_address','')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'));
    v_postal:=translate(btrim(coalesce(p_address->>'postal_code','')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789');
    v_additional:=translate(btrim(coalesce(p_address->>'additional_number','')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789');
    v_building:=translate(btrim(coalesce(p_address->>'building','')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789');
    if length(v_street)>150 or (v_short<>'' and v_short!~'^[A-Z]{4}[0-9]{4}$')
      or (v_postal<>'' and v_postal!~'^[0-9]{5}$') or (v_additional<>'' and v_additional!~'^[0-9]{4}$')
      or (v_building<>'' and v_building!~'^[0-9]{4}$') then
      raise exception 'delivery_invalid_national_address' using errcode='22023';
    end if;
  else
    -- لا تُحفظ حقول محلية مخفية حتى لو أرسلها متصفح معدل.
    v_street:=''; v_short:=''; v_postal:=''; v_additional:=''; v_building:='';
  end if;
  v_line:=concat_ws('، ',v_country,v_city,nullif(v_district,''),nullif(v_street,''),nullif(v_postal,''),nullif(v_additional,''),nullif(v_short,''));
  if length(v_line)>500 then raise exception 'delivery_invalid_address' using errcode='22023'; end if;
  -- الدالة الأصلية تتحقق من UUID والإحداثيات وحد العناوين وتعزل الحساب وتضبط الافتراضي ذرياً.
  perform public.save_delivery_address(v_uid,p_address || jsonb_build_object(
    'label',left(concat_ws(' · ',v_city,nullif(v_district,'')),60),'address_line',v_line,
    'building',v_building,'floor','','apartment','','notes',''));
  v_id:=(p_address->>'id')::uuid;
  update public.delivery_addresses set address_scope=v_scope,country=v_country,city=v_city,district=v_district,
    street=v_street,short_address=v_short,postal_code=v_postal,additional_number=v_additional
    where user_id=v_uid and id=v_id;
  return query select d.* from public.delivery_addresses d where d.user_id=v_uid order by d.created_at,d.id;
end $$;
revoke all on function public.save_structured_delivery_address(uuid,jsonb) from public,anon;
grant execute on function public.save_structured_delivery_address(uuid,jsonb) to authenticated;

-- دالة الوجهة أدناه تحفظ أولوية الطلب الحالي وتمنع اعتماد عنوان دولي لشحن محلي.
create or replace function public.get_domestic_shipping_destination(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare dest jsonb; saved public.delivery_addresses%rowtype; profile public.profiles%rowtype;
begin
  if auth.uid() is null or not exists(select 1 from public.orders where id=p_order_id and buyer_id=auth.uid()) then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  select s.destination into dest from public.order_shipments s where s.order_id=p_order_id
    and public.shipping_is_saudi_country(s.destination->>'country');
  if dest is not null then return (dest-'port') || jsonb_build_object('scope','domestic','country','Saudi Arabia'); end if;
  select * into saved from public.delivery_addresses where user_id=auth.uid() and is_default;
  if found then
    if saved.address_scope in ('international','legacy_review') or (saved.country<>'' and not public.shipping_is_saudi_country(saved.country)) then
      raise exception 'shipping_saved_address_not_domestic' using errcode='22023';
    end if;
    select * into profile from public.profiles where id=auth.uid();
    if length(btrim(coalesce(profile.full_name,'')))=0 or length(btrim(coalesce(profile.phone,'')))=0 then
      raise exception 'shipping_contact_missing' using errcode='22023';
    end if;
    return jsonb_build_object('scope','domestic','country','Saudi Arabia',
      'address',concat_ws(' · ',saved.address_line,nullif(saved.building,''),nullif(saved.floor,''),nullif(saved.apartment,'')),
      'contact',profile.full_name,'phone',profile.phone,'phone_country_code',profile.country_code,
      'latitude',saved.latitude,'longitude',saved.longitude,'delivery_notes',saved.notes,'saved_address_id',saved.id,
      'city',saved.city,'district',saved.district,'street',saved.street,'building',saved.building,
      'postal_code',saved.postal_code,'short_address',saved.short_address,'additional_number',saved.additional_number);
  end if;
  select s.destination into dest from public.order_shipments s join public.orders o on o.id=s.order_id
    where o.buyer_id=auth.uid() and s.order_id<>p_order_id and public.shipping_is_saudi_country(s.destination->>'country')
    order by s.updated_at desc,s.order_id limit 1;
  if dest is null then return null; end if;
  return (dest-'port') || jsonb_build_object('scope','domestic','country','Saudi Arabia');
end $$;
revoke all on function public.get_domestic_shipping_destination(uuid) from public,anon;
grant execute on function public.get_domestic_shipping_destination(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
