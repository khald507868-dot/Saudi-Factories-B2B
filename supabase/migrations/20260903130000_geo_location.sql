-- ============================================================
--  الموقع الجغرافي — 2026-09-03
--
--  بطلب المالك: أيقونة موقع في الشريط العلوي، يلصق فيها
--  المستخدم رابط موقعه من قوقل ماب فتُستخرج منه الإحداثيات.
--
--  والفرق بين الحسابين مقصود:
--    • المصنع  → تظهر نقطة خضراء في موقعه على الخريطة للجميع.
--    • الفرد    → لا يظهر على الخريطة إطلاقاً؛ موقعه محفوظ
--                 لتوصيل الطلبية وحدها.
--
--  ولذلك يعيش العمودان في جدولين منفصلين لا في واحد:
--  factories عام يقرؤه الزوار، وprofiles خاص تحرسه RLS.
--  فخصوصية الأفراد مضمونة ببنية الجداول لا بشرطٍ في الواجهة
--  يمكن نسيانه.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

-- ---------- 1) إحداثيات المصنع (عامة) ----------
alter table public.factories add column if not exists lat numeric(9, 6);
alter table public.factories add column if not exists lng numeric(9, 6);
-- الرابط الأصلي كما لصقه المستخدم: يُعرض له ليتأكد، ويسمح
-- بإعادة الاستخراج لاحقاً لو تغيّرت طريقة القراءة.
alter table public.factories add column if not exists map_url text not null default '';

-- ---------- 2) إحداثيات الفرد (خاصة) ----------
alter table public.profiles add column if not exists lat numeric(9, 6);
alter table public.profiles add column if not exists lng numeric(9, 6);
alter table public.profiles add column if not exists map_url text not null default '';

-- ---------- 3) حدود منطقية للإحداثيات ----------
-- خارج المدى تعني رابطاً أُسيء قراءته، فتُرفض عند الكتابة
-- بدل أن تُرسم نقطة في وسط المحيط.
do $guard$
begin
  if not exists (select 1 from pg_constraint where conname = 'factories_lat_check') then
    alter table public.factories
      add constraint factories_lat_check check (lat is null or (lat between -90 and 90));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'factories_lng_check') then
    alter table public.factories
      add constraint factories_lng_check check (lng is null or (lng between -180 and 180));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_lat_check') then
    alter table public.profiles
      add constraint profiles_lat_check check (lat is null or (lat between -90 and 90));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_lng_check') then
    alter table public.profiles
      add constraint profiles_lng_check check (lng is null or (lng between -180 and 180));
  end if;
end
$guard$;

-- ---------- 4) فهرس للمصانع التي لها موقع ----------
-- الخريطة تقرأ المصانع ذات الإحداثيات وحدها.
create index if not exists factories_geo_idx
  on public.factories(lat, lng)
  where lat is not null and lng is not null;


-- ============================================================
--  تحقّق: يجب أن تظهر ستة صفوف — ثلاثة لكل جدول
-- ============================================================
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('factories', 'profiles')
   and column_name in ('lat', 'lng', 'map_url')
 order by table_name, column_name;
