-- ربط عنوان الحساب الافتراضي بطلب قائم بعد معاينته، دون تبديل وجهات الطلبات تلقائياً.
begin;
create or replace function public.get_saved_shipping_destination(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare saved public.delivery_addresses%rowtype; profile public.profiles%rowtype;
begin
  if auth.uid() is null or not public.account_can_write() or not exists(
    select 1 from public.orders where id=p_order_id and buyer_id=auth.uid()
  ) then raise exception 'shipping_access_denied' using errcode='42501'; end if;
  select * into saved from public.delivery_addresses where user_id=auth.uid() and is_default;
  if not found then raise exception 'shipping_saved_address_missing' using errcode='22023'; end if;
  if saved.address_scope is distinct from 'domestic' or not public.shipping_is_saudi_country(saved.country) then
    raise exception 'shipping_saved_address_not_domestic' using errcode='22023';
  end if;
  select * into profile from public.profiles where id=auth.uid();
  if length(btrim(coalesce(profile.full_name,'')))=0 or length(btrim(coalesce(profile.phone,'')))=0 then
    raise exception 'shipping_contact_missing' using errcode='22023';
  end if;
  return jsonb_build_object('scope','domestic','country','Saudi Arabia',
    'address',concat_ws(' · ',saved.address_line,nullif(saved.building,'')),
    'contact',profile.full_name,'phone',profile.phone,'phone_country_code',profile.country_code,
    'latitude',saved.latitude,'longitude',saved.longitude,'delivery_notes',saved.notes,'saved_address_id',saved.id,
    'city',saved.city,'district',saved.district,'street',saved.street,'building',saved.building,
    'postal_code',saved.postal_code,'short_address',saved.short_address,'additional_number',saved.additional_number);
end $$;
revoke all on function public.get_saved_shipping_destination(uuid) from public,anon;
grant execute on function public.get_saved_shipping_destination(uuid) to authenticated;

create or replace function public.link_saved_shipping_address(p_order_id uuid,p_revision integer,p_expected_destination jsonb)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; s public.order_shipments%rowtype; dest jsonb;
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
  dest:=public.get_saved_shipping_destination(o.id);
  if p_expected_destination is distinct from dest then raise exception 'shipping_stale' using errcode='22023'; end if;
  -- إعادة الربط بالعنوان نفسه لا تُبطل عرضاً صحيحاً ولا تكرر الإشعارات.
  if s.destination=dest and s.delivery_type='door' then return s; end if;
  return public.update_manual_shipping(o.id,'destination',jsonb_build_object(
    'revision',s.revision,'destination',dest,'delivery_type','door'));
end $$;
revoke all on function public.link_saved_shipping_address(uuid,integer,jsonb) from public,anon;
grant execute on function public.link_saved_shipping_address(uuid,integer,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
