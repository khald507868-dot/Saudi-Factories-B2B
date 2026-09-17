-- فحص فقط، دون تعديل البيانات أو استدعاء إنشاء طلب.
-- طابق التعريف المعروض مع ترحيل 20260917100000_checkout_security.sql.
select p.oid::regprocedure::text as signature,
  p.prosecdef as security_definer, p.proconfig as settings,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('create_order_from_cart','tier_unit_price');

-- عدم التطابق يستدعي مراجعة محاسبية؛ لا يثبت الاستغلال ولا يُصحَّح تلقائياً.
-- الناتج عدد إجمالي فقط، دون هويات العملاء أو تفاصيل طلباتهم.
select count(*) as orders_with_item_subtotal_mismatch
from public.orders o
left join (
  select order_id, sum(line_total) as item_subtotal
  from public.order_items group by order_id
) i on i.order_id=o.id
where o.subtotal is distinct from coalesce(i.item_subtotal,0);
