-- ============================================================
--  حذف الحساب التجريبي المستخدم في اختبار الأمان
--
--  أنشأتُ حساب sec.test.factory@gmail.com لاختبار هل يستطيع
--  مورّد التعديل على مصنع مورّد آخر. تأكيد البريد منع إكمال
--  الاختبار، فلا حاجة للحساب — ووجوده يعني صفّ مصنع زائد
--  في جدولك.
--
--  الحذف من auth.users يحذف تلقائياً صفّ profiles وصفّ
--  factories معه (بسبب on delete cascade).
--
--  الخطوات: Supabase ← SQL Editor ← New query ← لصق ← Run
-- ============================================================

delete from auth.users
where email = 'sec.test.factory@gmail.com';


-- تحقّق: يجب ألا يبقى إلا مصنعك أنت
select p.email,
       f.id     as factory_id,
       f.name   as factory_name,
       f.status
from public.profiles p
left join public.factories f on f.owner_id = p.id
where p.account_type = 'factory'
order by p.email;
