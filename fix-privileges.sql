-- ============================================================
--  إصلاح أمني — منع تصعيد الصلاحيات
--
--  كُشفت ثغرتان بالاختبار الفعلي:
--   1) المصنع كان يستطيع كتابة status='approved' فيعتمد نفسه
--   2) أي مستخدم كان يستطيع كتابة is_admin=true فيصبح مديرًا
--
--  السبب: with check تتحقق ممّن يعدّل، لا ممّا يعدّل.
--  الحل: مُشغِّلات تعيد الأعمدة الحساسة إلى قيمتها القديمة
--        ما لم يكن المعدِّل مديرًا.
--
--  Supabase → SQL Editor → الصق → Run
-- ============================================================

-- ---------- حماية is_admin ----------
create or replace function public.guard_profile_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- المدير وحده يمنح صلاحية الإدارة
  if new.is_admin is distinct from old.is_admin then
    if not public.is_admin() then
      new.is_admin := old.is_admin;
    end if;
  end if;

  -- نوع الحساب لا يتغيّر بعد التسجيل
  new.account_type := old.account_type;
  new.id           := old.id;

  return new;
end;
$fn$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_columns();


-- ---------- حماية status ----------
create or replace function public.guard_factory_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- الإدارة وحدها تعتمد أو ترفض
  if new.status is distinct from old.status then
    if not public.is_admin() then
      new.status := old.status;
    end if;
  end if;

  if new.rejection_reason is distinct from old.rejection_reason then
    if not public.is_admin() then
      new.rejection_reason := old.rejection_reason;
    end if;
  end if;

  -- الملكية لا تُنقل
  new.owner_id := old.owner_id;

  return new;
end;
$fn$;

drop trigger if exists factories_guard on public.factories;
create trigger factories_guard
  before update on public.factories
  for each row execute function public.guard_factory_columns();


-- ---------- تنظيف بيانات الاختبار ----------
update public.profiles  set is_admin = false where is_admin = true;
update public.factories set status = 'pending' where status = 'approved';
