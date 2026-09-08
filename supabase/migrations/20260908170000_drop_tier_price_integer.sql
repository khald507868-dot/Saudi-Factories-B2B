-- ============================================================
-- إتمام الإصلاح: حذف توقيع integer المكرّر
-- ------------------------------------------------------------
-- الملفّ السابق أضاف نسخة numeric وأبقى نسخة integer ظنّاً
-- أنّ مواضع تناديها بعدد صحيح. والفحص أثبت خطأ ذلك: كلّ
-- استدعاء في المشروع يمرّر ci.quantity وعمودها numeric.
--
-- ووجود التوقيعين معاً أنشأ عطلاً جديداً: واجهة REST لا
-- تستطيع الاختيار بينهما فترفض النداء بـPGRST203 «Could not
-- choose the best candidate function» — فيبقى الشراء
-- معطّلاً بسبب آخر.
--
-- فيُحذف توقيع integer وحده. وحذف دالّة بتوقيعها لا يمسّ
-- التوقيع الآخر.
--
-- يُطبَّق بعد 20260908160000 مباشرة:
-- Supabase → SQL Editor → New query → لصق → Run
-- ============================================================

drop function if exists public.tier_unit_price(bigint, integer);

-- تحقّق: يجب أن يبقى سطر واحد — النسخة numeric ---------------
select p.oid::regprocedure::text as signature
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'tier_unit_price'
 order by 1;
