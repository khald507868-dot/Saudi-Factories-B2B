-- ============================================================
-- فتح التقييم لكلّ حساب مسجّل (بطلب المالك)
-- ------------------------------------------------------------
-- كان التقييم لمن اشترى وحده. والمالك يريده لكلّ مسجّل،
-- مع بقاء «مراجعة واحدة لكلّ حساب» — وهو مضمون أصلاً بقيد
-- unique (product_id, author_id) في الجدول، فلا يحتاج تغييراً.
--
-- ويبقى وسم «مشترٍ موثّق» لمن اشترى فعلاً: get_product_reviews
-- تُرجِع is_verified محسوبةً من الطلبات، فالوسم يظلّ صادقاً
-- ويميّز التجربة الحقيقية من الرأي المجرّد.
--
-- ما يبقى على حاله:
--   author_id = auth.uid()  — لا يكتب أحد باسم غيره
--   rating between 1 and 5  — لا قيم خارج النطاق
--   الحذف للمقيّم والمشرف وحدهما — لا لصاحب المصنع
--
-- والمالك يعلم أنّ هذا يفتح باباً للتقييمات المزيّفة
-- ولمهاجمة المنافسين؛ قُرّر بعد بيان ذلك.
--
-- يُطبَّق بعد 20260908150000:
-- Supabase → SQL Editor → New query → لصق → Run
-- ============================================================

-- 1) سياسة الكتابة: الحساب وحده لا الشراء -------------------
drop policy if exists product_reviews_insert on public.product_reviews;
create policy product_reviews_insert
  on public.product_reviews
  for insert
  to authenticated
  with check (author_id = auth.uid());

-- 2) الوسم يُحسب من الطلبات، لا من كون الكاتب مقيّماً --------
-- is_verified عمود محسوب لا مخزّن: لو خُزّن لصار قابلاً
-- للتزوير عند الكتابة، ولتقادم إن أُلغي الطلب لاحقاً.
create or replace function public.get_product_reviews(
  p_product_id bigint,
  p_limit      integer default 20,
  p_offset     integer default 0
) returns table (
  id           bigint,
  rating       smallint,
  body         text,
  created_at   timestamptz,
  author_name  text,
  author_image text,
  is_mine      boolean,
  is_verified  boolean
)
language sql
stable
security definer
set search_path = public
as $fn$
  select r.id,
         r.rating,
         r.body,
         r.created_at,
         coalesce(nullif(p.full_name, ''), 'مشترٍ') as author_name,
         coalesce(p.company_image, '')              as author_image,
         (r.author_id = auth.uid())                 as is_mine,
         public.has_purchased_product(p_product_id, r.author_id) as is_verified
    from public.product_reviews r
    left join public.profiles p on p.id = r.author_id
   where r.product_id = p_product_id
   order by r.created_at desc
   limit  greatest(1, least(coalesce(p_limit, 20), 100))
   offset greatest(0, coalesce(p_offset, 0));
$fn$;

revoke all on function public.get_product_reviews(bigint, integer, integer) from public;
grant execute on function public.get_product_reviews(bigint, integer, integer) to anon, authenticated;

-- 3) has_purchased_product تُنادى الآن بمعرّف كاتب غير المنادي،
--    فتحتاج صلاحية القراءة لكلّ مسجّل ولزائر يقرأ المراجعات.
grant execute on function public.has_purchased_product(bigint, uuid) to anon;

-- 4) can_review_product: صار الجواب «نعم» لكلّ مسجّل ---------
-- تبقى الدالّة لأنّ الواجهة تناديها، وتُرجِع الآن ما إذا كان
-- المستخدم مسجّلاً وهل سبق أن قيّم.
create or replace function public.can_review_product(
  p_product_id bigint
) returns table (
  can_review  boolean,
  has_review  boolean
)
language sql
stable
security definer
set search_path = public
as $fn$
  select (auth.uid() is not null),
         exists (
           select 1 from public.product_reviews r
            where r.product_id = p_product_id
              and r.author_id  = auth.uid()
         );
$fn$;

revoke all on function public.can_review_product(bigint) from public;
grant execute on function public.can_review_product(bigint) to authenticated;

-- 5) تحقّق ---------------------------------------------------
select 'reviews open to all signed-in users' as status;
