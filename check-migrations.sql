-- ============================================================
-- فحص: هل طُبِّقت كل ترحيلات الباك إند حتى 2026-09-05؟
-- هذا الملف يقرأ فقط ولا يعدّل أي شيء — تشغيله آمن تمامًا.
--
-- الطريقة: Supabase -> SQL Editor -> New query -> الصق -> Run
-- اقرأ عمود "الحالة" في النتيجة.
-- ============================================================

select
  'الجداول الجديدة' as "الفحص",
  count(*) || ' من 8' as "الموجود",
  case when count(*) = 8
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end as "الحالة"
from information_schema.tables
where table_schema = 'public'
  and table_name in ('posts','custom_prices','carts','cart_items','orders',
                     'order_items','payment_attempts','favorites')

union all

select
  'الدوال الخادمية',
  count(distinct p.proname) || ' من 11',
  case when count(distinct p.proname) = 11
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_or_create_cart','add_to_cart',
                    'create_order_from_cart','save_factory_content',
                    'sync_product_media','get_conversation_peers',
                    'touch_conversation_from_message',
                    'get_conversation_summaries','mark_conversation_read',
                    'get_unread_message_total','get_public_stats')

union all

select
  'أعمدة الرسائل المضافة',
  count(*) || ' من 4',
  case when count(*) = 4
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from information_schema.columns
where table_schema = 'public'
  and table_name = 'messages'
  and column_name in ('custom_price_id','client_key','read_at','updated_at')

union all

select
  'تفاصيل المنتج',
  count(*) || ' من 5',
  case when count(*) = 5
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from information_schema.columns
where table_schema = 'public'
  and table_name = 'products'
  and column_name in ('description','material','sizes','colors','moq')

union all

select
  'أعمدة الموقع الجغرافي',
  count(*) || ' من 6',
  case when count(*) = 6
       then 'تمام - مطبَّقة'
       else 'ناقص - لم تُطبَّق' end
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles','factories')
  and column_name in ('lat','lng','map_url')

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
  and trigger_name = 'messages_touch_conversation'

union all

select
  'RPC الخاصة المحجوبة عن الزائر',
  count(*) filter (
    where not has_function_privilege('anon', p.oid, 'execute')
  ) || ' من 8',
  case when count(*) = 8
             and bool_and(not has_function_privilege('anon', p.oid, 'execute'))
       then 'تمام - محمية'
       else 'ناقص - طبّق ترحيل الصلاحيات' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('save_factory_content','get_or_create_cart','add_to_cart',
                    'create_order_from_cart','get_conversation_peers',
                    'get_conversation_summaries','mark_conversation_read',
                    'get_unread_message_total');
