-- ============================================================
--  إضافة عمود الترخيص الصناعي إلى جدول المصانع
--
--  لماذا ملف منفصل؟ لأن schema.sql يستخدم
--  create table if not exists — فالجدول موجود عندك أصلاً،
--  وإعادة لصق schema.sql لن تضيف العمود الجديد إطلاقاً.
--
--  كيف تشغّله:
--    Supabase → SQL Editor → New query → الصق هذا → Run
--
--  آمن للتكرار: if not exists تعني أن تشغيله مرّتين لا يضرّ.
-- ============================================================

alter table public.factories
  add column if not exists industrial_license text not null default '';

comment on column public.factories.industrial_license
  is 'رقم الترخيص الصناعي — عشرة أرقام حدّاً أقصى، تفرضها الواجهة';


-- ============================================================
--  تحقّق: يجب أن يظهر السطران معاً بعد التشغيل
-- ============================================================

select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'factories'
  and column_name in ('commercial_register', 'industrial_license')
order by column_name;
