-- ============================================================
--  صور الفئات — 2026-09-06
--
--  بطلب المالك: صورة لكل فئة صناعية، يضعها مدير الموقع وحده،
--  ويراها الجميع ثابتة لا يستطيع أحد تغييرها.
--
--  لماذا جدول على الخادم ولا حفظ في المتصفّح:
--  الصورة يجب أن يراها كل زائر، لا أن تبقى في جهاز المدير.
--  و"لا يمكن تغييرها" لا تتحقّق بإخفاء زر من الواجهة — من يعرف
--  الطلب يرسله مباشرة. المنع الحقيقي هنا في سياسات RLS أدناه:
--  الخادم نفسه يرفض الكتابة من غير المدير.
--
--  المفتاح هو الاسم الإنجليزي للفئة، لأنه المفتاح ذاته المستعمل
--  في عمود factories.industry وفي روابط ?cat= — فلا يظهر مفتاح
--  ثانٍ يحتاج مزامنة، ولا تنكسر الصور عند تغيير لغة الواجهة.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

create table if not exists public.category_images (
  category_en text primary key,
  image_url   text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users (id) on delete set null
);

alter table public.category_images enable row level security;


-- ------------------------------------------------------------
--  القراءة: مفتوحة للجميع
--  الصفحة الرئيسية تفتح للزائر بلا حساب، فلا بدّ أن يراها.
-- ------------------------------------------------------------
drop policy if exists category_images_select_all on public.category_images;
create policy category_images_select_all
  on public.category_images
  for select
  using (true);


-- ------------------------------------------------------------
--  الكتابة: للمدير وحده
--
--  ثلاث سياسات منفصلة (إدراج/تعديل/حذف) لأن policy واحدة
--  لـ all لا تُطبّق with check على الحذف، وتترك ثغرة صامتة.
--
--  is_admin() موجودة أصلاً في schema.sql وتقرأ profiles.is_admin
--  للمستخدم الحالي، وهي security definer فلا تصطدم بسياسة
--  profiles نفسها.
-- ------------------------------------------------------------
drop policy if exists category_images_insert_admin on public.category_images;
create policy category_images_insert_admin
  on public.category_images
  for insert
  with check (public.is_admin());

drop policy if exists category_images_update_admin on public.category_images;
create policy category_images_update_admin
  on public.category_images
  for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists category_images_delete_admin on public.category_images;
create policy category_images_delete_admin
  on public.category_images
  for delete
  using (public.is_admin());


-- ------------------------------------------------------------
--  حارس: يمنع تزوير حقلي التتبّع
--
--  updated_by يُكتب من auth.uid() لا مما يرسله العميل، وإلا
--  نسب المدير تعديله إلى شخص آخر. ونفس المنطق لـ updated_at.
-- ------------------------------------------------------------
create or replace function public.category_images_stamp()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$fn$;

drop trigger if exists category_images_stamp_trg on public.category_images;
create trigger category_images_stamp_trg
  before insert or update on public.category_images
  for each row execute function public.category_images_stamp();


-- ------------------------------------------------------------
--  رفع الملفّات: مجلّد category/ داخل دلو factory-media
--
--  سياسات الدلو الحالية تسمح لأي مستخدم مسجّل بالرفع داخل
--  مجلّد يحمل معرّفه. المدير يرفع داخل مجلّده هو، والرابط
--  الناتج عام للقراءة — وهو ما نحتاجه بالضبط: الرفع محكوم،
--  والعرض مفتوح.
-- ------------------------------------------------------------


-- ============================================================
--  تحقّق: يجب أن تظهر أربع سياسات (قراءة + ثلاث كتابة)
-- ============================================================
select policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename  = 'category_images'
 order by policyname;
