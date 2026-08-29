-- ============================================================
-- فحص: هل طُبِّقت ترحيلات 2026-08-27 و2026-08-29 على قاعدة البيانات؟
-- هذا الملف يقرأ فقط ولا يعدّل أي شيء — تشغيله آمن تمامًا.
--
-- الطريقة: Supabase -> SQL Editor -> New query -> الصق -> Run
-- اقرأ عمود "الحالة" في النتيجة.
-- ============================================================

select
  'الجداول الجديدة' as "الفحص",
  count(*) || ' من 5' as "الموجود",
  case when count(*) = 5
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end as "الحالة"
from information_schema.tables
where table_schema = 'public'
  and table_name in ('carts','cart_items','orders','order_items','payment_attempts')

union all

select
  'الدوال الخادمية',
  count(*) || ' من 5',
  case when count(*) = 5
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_or_create_cart','add_to_cart',
                    'create_order_from_cart','save_factory_content',
                    'sync_product_media')

union all

select
  'أعمدة المرفقات في messages',
  count(*) || ' من 2',
  case when count(*) = 2
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from information_schema.columns
where table_schema = 'public'
  and table_name = 'messages'
  and column_name in ('attachment_url','attachment_type')

union all

select
  'دوال الرسائل الفورية',
  count(*) || ' من 2',
  case when count(*) = 2
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_conversation_peers','touch_conversation_from_message')

union all

select
  'مشغّل ترتيب المحادثات',
  count(*) || ' من 1',
  case when count(*) = 1
       then 'تمام - مطبَّق'
       else 'ناقص - لم يُطبَّق' end
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'messages'
  and trigger_name = 'messages_touch_conversation';
