-- ============================================================
-- حذف المنتج الفارغ رقم 4 (بلا اسم ولا سعر ولا صور)
--
-- هذا الملف *يحذف* — على عكس ملفات الفحص السابقة.
-- شرط الحذف يشترط أن تكون كل الحقول فارغة فعلًا،
-- فلو كان المنتج قد عُبّئ بينهما لن يُحذف شيء.
--
-- Supabase -> SQL Editor -> New query -> الصق -> Run
-- ============================================================

-- 1) يُزال أولًا من أي سلة يحتويها (وإلا منع المفتاح الأجنبي الحذف)
delete from cart_items
where product_id = 4;

-- 2) ثم المنتج نفسه، بشرط أن يكون فارغًا
delete from products
where id = 4
  and coalesce(nullif(trim(name), ''), '') = ''
  and price is null
  and coalesce(array_length(images, 1), 0) = 0;

-- 3) النتيجة: كم منتجًا بقي؟ (Supabase يعرض آخر أمر فقط)
select
  count(*) as "عدد المنتجات المتبقية",
  count(*) filter (
    where coalesce(nullif(trim(name), ''), '') = '' and price is null
  ) as "منها فارغة"
from products;
