-- ============================================================
-- فحص الحماية: هل RLS مفعّل على الجداول الجديدة؟
-- يقرأ فقط - لا يعدّل شيئًا. آمن تمامًا.
-- ============================================================
select
  c.relname as "الجدول",
  case when c.relrowsecurity then 'مفعّل' else 'معطّل - خطر' end as "الحماية RLS",
  (select count(*) from pg_policies p
    where p.schemaname = 'public' and p.tablename = c.relname) as "عدد السياسات"
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in ('carts','cart_items','orders','order_items',
                    'payment_attempts','posts','custom_prices',
                    'conversations','messages','profiles','factories','products')
order by c.relrowsecurity, c.relname;
