-- ============================================================
--  حقول ملف المصنع: الموقع الإلكتروني والقطاع وحجم الشركة
--
--  لماذا ملف منفصل؟ لأن schema.sql يستخدم
--  create table if not exists — فالجدول موجود عندك أصلاً،
--  وإعادة لصق schema.sql لن تضيف الأعمدة الجديدة إطلاقًا.
--
--  كيف تشغّله:
--    Supabase → SQL Editor → New query → الصق هذا → Run
--
--  آمن للتكرار: if not exists تعني أن تشغيله مرّتين لا يضرّ.
-- ============================================================

alter table public.factories
  add column if not exists website      text not null default '',
  add column if not exists industry     text not null default '',
  add column if not exists company_size text not null default '';

comment on column public.factories.website
  is 'الموقع الإلكتروني للمصنع — تتحقّق الواجهة من الصيغة';
comment on column public.factories.industry
  is 'القطاع — يقابل معرّفات الفئات في i18n.js';
comment on column public.factories.company_size
  is 'حجم الشركة: نطاق عدد الموظفين مثل 51-200';


-- ============================================================
--  تحقّق: يجب أن تظهر الأعمدة الثلاثة بعد التشغيل
-- ============================================================

select column_name, data_type
from   information_schema.columns
where  table_schema = 'public'
  and  table_name   = 'factories'
  and  column_name in ('website', 'industry', 'company_size')
order  by column_name;
