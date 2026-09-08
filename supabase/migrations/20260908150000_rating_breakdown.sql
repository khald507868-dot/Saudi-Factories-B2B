-- ============================================================
-- توزيع النجوم، وبطاقة ثقة المورّد
-- ------------------------------------------------------------
-- دالّتان للعرض وحدهما، لا تكتبان شيئاً:
--   get_rating_breakdown  — كم مراجعة لكلّ درجة من ١ إلى ٥
--   get_factory_summary   — اعتماد المصنع وعدد منتجاته ومدينته
--
-- كلتاهما security definer لأنّ المشتري لا يملك قراءة صفوف
-- المصانع غير المعتمدة ولا عدّ منتجات غيره، وهما تُرجِعان
-- أرقاماً مجمّعة لا صفوفاً.
--
-- يُطبَّق مرّة واحدة:
-- Supabase → SQL Editor → New query → لصق → Run
-- ============================================================

-- 1) توزيع النجوم ------------------------------------------
-- خمسة صفوف دائماً حتّى لو كانت درجة بلا مراجعات: الواجهة
-- ترسم شريطاً فارغاً لها، ولو غاب الصفّ لاختلّ الترتيب.
create or replace function public.get_rating_breakdown(
  p_product_id bigint
) returns table (
  rating smallint,
  cnt    bigint
)
language sql
stable
security definer
set search_path = public
as $fn$
  select g.rating::smallint,
         count(r.id)
    from generate_series(1, 5) as g(rating)
    left join public.product_reviews r
           on r.product_id = p_product_id
          and r.rating = g.rating
   group by g.rating
   order by g.rating desc;
$fn$;

revoke all on function public.get_rating_breakdown(bigint) from public;
grant execute on function public.get_rating_breakdown(bigint) to anon, authenticated;

-- 2) ملخّص المصنع ------------------------------------------
-- عدد المنتجات يُحسب هنا لا في العميل: العميل لا يملك عدّ
-- صفوف مصنع غيره، وجلبها كلّها ليعدّها هدر.
create or replace function public.get_factory_summary(
  p_factory_id bigint
) returns table (
  is_approved    boolean,
  product_count  bigint,
  city           text
)
language sql
stable
security definer
set search_path = public
as $fn$
  select (f.status = 'approved'),
         (select count(*) from public.products p where p.factory_id = f.id),
         coalesce(f.address_city, '')
    from public.factories f
   where f.id = p_factory_id;
$fn$;

revoke all on function public.get_factory_summary(bigint) from public;
grant execute on function public.get_factory_summary(bigint) to anon, authenticated;

-- 3) تحقّق ---------------------------------------------------
select 'rating breakdown ready' as status;
