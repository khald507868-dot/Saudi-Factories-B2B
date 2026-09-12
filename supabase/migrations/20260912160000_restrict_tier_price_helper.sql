-- حصر حساب سعر الشريحة بالاستدعاء الداخلي عند إنشاء الطلب.
begin;

do $check$
begin
  if exists (
    select 1 from pg_policies
    where schemaname in ('public', 'storage')
      and concat(qual, ' ', with_check) ~ 'tier_unit_price[[:space:]]*\('
  ) then
    raise exception 'Review policy dependencies before restricting tier_unit_price';
  end if;
  if not exists (
    select 1 from pg_proc checkout
    join pg_proc helper on helper.proowner = checkout.proowner
    where checkout.oid = to_regprocedure('public.create_order_from_cart(bigint,uuid)')
      and helper.oid = to_regprocedure('public.tier_unit_price(bigint,numeric)')
      and checkout.prosecdef
  ) then
    raise exception 'Checkout must execute as the tier-price helper owner';
  end if;
end;
$check$;

-- لا تستدعي واجهتا الويب وFlutter هذه الدالة مباشرة؛ يستدعيها إنشاء الطلب.
-- لا نغيّر الأسعار أو معادلات الحساب أو بيانات الطلبات.
revoke execute on function public.tier_unit_price(bigint, numeric)
  from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
