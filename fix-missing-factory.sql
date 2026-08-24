-- ============================================================
--  إصلاح: حساب مصنع بلا صفّ في جدول factories
--
--  السبب: المشغّل on_auth_user_created هو الذي يُنشئ صفّ
--  المصنع لحظة التسجيل. فمن سجّل قبل إضافة المشغّل — أو
--  أُنشئ حسابه يدوياً — يبقى account_type = 'factory' في
--  profiles بلا صفّ مقابل في factories، فلا تجد صفحة
--  الحساب ما تعرضه.
--
--  هذا الملف يُصلح الحالة لكل الحسابات المتأثرة دفعةً
--  واحدة، لا لحساب بعينه — وهو آمن للتشغيل أكثر من مرة
--  لأن on conflict do nothing يمنع التكرار، و owner_id
--  فريد في الجدول أصلاً.
--
--  الخطوات: Supabase ← SQL Editor ← New query ← لصق ← Run
-- ============================================================

-- 1) أنشئ الصفّ الناقص لكل حساب مصنع لا صفّ له
insert into public.factories (owner_id, name, status)
select p.id,
       coalesce(nullif(p.full_name, ''), ''),
       'pending'
from public.profiles p
where p.account_type = 'factory'
  and not exists (
    select 1 from public.factories f where f.owner_id = p.id
  )
on conflict (owner_id) do nothing;

-- 2) اعرض النتيجة: كل حسابات المصانع وصفوفها
--    الحالة الصحيحة: لكل صفّ رقم مصنع (factory_id) غير فارغ
select p.email,
       p.account_type,
       f.id     as factory_id,
       f.name   as factory_name,
       f.status
from public.profiles p
left join public.factories f on f.owner_id = p.id
where p.account_type = 'factory'
order by p.email;
