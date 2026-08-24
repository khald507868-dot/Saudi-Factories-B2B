-- ============================================================
--  اعتماد مصنعي (رقم 8)
--
--  لماذا لم ينجح التحديث السابق؟
--  على جدول factories حارس اسمه factories_guard يمنع
--  تغيير status إلا لمن هو admin — والتحقق يتم بدالة
--  is_admin() التي تقرأ المستخدم المسجّل حالياً.
--
--  وفي محرّر SQL لا يوجد مستخدم مسجّل، فترجع is_admin()
--  قيمة false، فيُعيد الحارس الحالة إلى pending بصمت
--  دون أي رسالة خطأ — ولهذا ظهر التشغيل ناجحاً بلا أثر.
--
--  الحل: نعطّل الحارس داخل معاملة واحدة، ونحدّث، ثم
--  نعيد تفعيله. وهو نفس الأسلوب المتبع في make-admin.sql
--  في هذا المشروع.
--
--  الخطوات: Supabase ← SQL Editor ← New query ← لصق ← Run
-- ============================================================

begin;

-- عطّل الحارس مؤقتاً
alter table public.factories disable trigger factories_guard;

-- اعتمد مصنع المالك، واملأ اسمه إن كان فارغاً
update public.factories f
set status = 'approved',
    name   = coalesce(nullif(f.name, ''), 'مصنعي')
from public.profiles p
where p.id = f.owner_id
  and p.email = 'khald507868@gmail.com';

-- أعد تفعيل الحارس فوراً — مهم: لا تتركه معطّلاً
alter table public.factories enable trigger factories_guard;

commit;


-- النتيجة: المفروض status = approved
select p.email,
       f.id     as factory_id,
       f.name   as factory_name,
       f.status
from public.profiles p
left join public.factories f on f.owner_id = p.id
where p.account_type = 'factory'
order by p.email;
