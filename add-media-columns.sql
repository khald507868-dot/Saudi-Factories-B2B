-- ============================================================
--  وسائط المنشورات والمنتجات
--
--  ما يضيفه:
--    posts.video       — مقطع المنشور (رابط تخزين)
--    products.images   — حتى خمس صور للمنتج الواحد
--
--  لماذا ملف منفصل؟ لأن schema.sql يستخدم
--  create table if not exists — فالجدولان موجودان عندك أصلاً،
--  وإعادة لصق schema.sql لن تضيف عموداً جديداً إطلاقًا.
--
--  كيف تشغّله:
--    Supabase → SQL Editor → New query → الصق هذا → Run
--
--  آمن للتكرار: if not exists تعني أن تشغيله مرّتين لا يضرّ.
-- ============================================================

-- 1) مقطع المنشور
alter table public.posts
  add column if not exists video text not null default '';

comment on column public.posts.video
  is 'مقطع المنشور — رابط تخزين. صورة أو مقطع، لا الاثنان معاً';


-- 2) صور المنتج — مصفوفة بدل صورة مفردة
alter table public.products
  add column if not exists images text[] not null default '{}';

comment on column public.products.images
  is 'حتى خمس صور للمنتج — الأولى هي الرئيسية';


-- 3) ترحيل الصور المفردة القائمة إلى المصفوفة
--    يُنفَّذ مرّة واحدة فعليًا: الشرط يستثني ما رُحِّل سابقًا
update public.products
   set images = array[image]
 where image is not null
   and image <> ''
   and cardinality(images) = 0;


-- 4) حدّ الخمس صور — على القاعدة لا على الواجهة وحدها
alter table public.products
  drop constraint if exists products_images_max;

alter table public.products
  add constraint products_images_max
  check (cardinality(images) <= 5);


-- ============================================================
--  للتحقّق بعد التشغيل — يجب أن تعود الأعمدة الجديدة:
--
--    select column_name, data_type
--      from information_schema.columns
--     where table_name in ('posts', 'products')
--       and column_name in ('video', 'images');
-- ============================================================
