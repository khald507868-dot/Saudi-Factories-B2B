-- ============================================================
--  منح صلاحية الإدارة لحسابك
--
--  لماذا لا يكفي تعديل المربّع من Table Editor؟
--  لأن حارس profiles_guard يعيد is_admin إلى false صامتًا
--  لكل من ليس مديرًا أصلاً — وأنت لست مديرًا بعد. فالمربّع
--  يرتدّ إلى false بلا رسالة خطأ، وهذا ما يحيّر المستخدم.
--
--  الحلّ: تعطيل الحارس وتحديث الصفّ وإعادة تفعيله في
--  معاملة واحدة — أي في لصقة واحدة كما هي هنا.
--
--  كيف تشغّله:
--    1) بدّل البريد أدناه ببريدك أنت
--    2) Supabase -> SQL Editor -> New query -> الصق -> Run
--
--  آمن للتكرار: تشغيله مرّتين لا يضرّ.
-- ============================================================

begin;

-- تعطيل الحارس مؤقّتًا داخل هذه المعاملة وحدها
alter table public.profiles disable trigger profiles_guard;

-- منح الصلاحية — بدّل البريد ببريدك
update public.profiles
set    is_admin = true
where  email = 'khald507868@gmail.com';

-- إعادة تفعيل الحارس فورًا — لا تتركه معطّلاً أبدًا
alter table public.profiles enable trigger profiles_guard;

commit;


-- ============================================================
--  تحقّق: يجب أن يظهر صفّك و is_admin = true
-- ============================================================

select id, email, full_name, account_type, is_admin
from   public.profiles
where  email = 'khald507868@gmail.com';


-- ============================================================
--  تحقّق ثانٍ: أن الحارس عاد يعمل
--  المطلوب: tgenabled = 'O'  (أي مُفعَّل)
--  لو ظهر 'D' فالحارس معطّل — أعد تشغيل السطر:
--    alter table public.profiles enable trigger profiles_guard;
-- ============================================================

select tgname, tgenabled
from   pg_trigger
where  tgrelid = 'public.profiles'::regclass
  and  tgname  = 'profiles_guard';
