-- Run once in Supabase SQL Editor. Safe to run again.
begin;
alter table public.home_promotions
  add column if not exists discount_category text,
  add column if not exists discount_percent numeric;
alter table public.home_promotions drop constraint if exists home_promotions_discount_target;
alter table public.home_promotions add constraint home_promotions_discount_target check (
  (discount_category is null and discount_percent is null) or
  (discount_category is not null and discount_percent is not null
   and length(btrim(discount_category)) between 1 and 120
   and discount_percent > 0 and discount_percent < 100 and target_url = '')
);

-- Link the existing artwork only while its image and empty destination still match.
-- Replacing an image or configuring a destination prevents this seed from overwriting it.
update public.home_promotions p
set discount_category = seed.category, discount_percent = seed.percent
from (values
 ('4ae0e25e-a4dc-4e83-8f1b-171b9464880b'::uuid, '113c9df0-2d9f-440d-8e6d-64d6f94c2548.png', 'Cleaning Products & Detergents', 30),
 ('89e3a8b3-b943-4720-957c-fd14ede04037'::uuid, '8936d669-60a2-4e9a-89ab-2fae15085cef.png', 'Plastics & Rubber', 50),
 ('01890172-818a-4150-974e-f40fa6ff4203'::uuid, 'cb537159-8914-45fe-99e3-b9a4ef69ac68.png', 'Paper, Printing & Packaging', 25),
 ('9c1fdd40-c31c-4bdf-a8f7-0340cd637615'::uuid, '89d24e90-f9eb-47be-8e96-87435af7f392.png', 'Food & Beverages', 40),
 ('8365c1ae-8cbd-4a39-9967-3dc7a1bada0b'::uuid, '4287fb7c-4d67-41e6-a5b7-600b3e748713.png', 'Clothing & Textiles', 35),
 ('047bbbde-e143-42cf-9505-2ef744d470b7'::uuid, 'c6d14284-7a8b-45bb-a5f4-4b96c7eb4dad.png', 'Electronics & Electrical Appliances', 25),
 ('88d17f27-1001-444a-8076-843398cadf5e'::uuid, '17fbad53-40f1-422c-b741-3034f9fc0910.png', 'Cosmetics & Personal Care', 45),
 ('4239fc64-adf6-4d43-a546-4921e60f7d6d'::uuid, 'db4b5564-4a40-4b59-8c30-06c72e240aba.png', 'Building & Construction Materials', 20),
 ('5b145364-69de-485b-a57a-887de97c6344'::uuid, '93887d65-b2c1-4114-9225-8a62488f17ff.png', 'Furniture & Furnishings', 30)
) as seed(id, filename, category, percent)
where p.id = seed.id and p.discount_category is null and p.discount_percent is null and p.target_url = ''
  and p.image_url = 'https://yhofxryhlrrwzztfowpa.supabase.co/storage/v1/object/public/promotion-media/b525a57e-7fb9-4cef-be81-ad1fc2695302/promotions/' || seed.filename;

-- Invoker permissions preserve existing catalog RLS; even admins see approved factories only.
-- No order, profile, or private pricing data is returned.
create or replace function public.get_promotion_quantity_offers(
  p_promotion_id uuid, p_offset integer default 0, p_limit integer default 20
) returns jsonb language sql stable security invoker set search_path = public as $fn$
with promotion as (
  select discount_category as category, discount_percent as percent
  from public.home_promotions
  where id = p_promotion_id and is_active and discount_category is not null
), catalog as (
  select p.id, p.name, p.image, p.images, p.tiers, greatest(coalesce(p.moq, 1), 1) as moq,
         f.name as factory_name
  from public.products p join public.factories f on f.id = p.factory_id
  join promotion ad on f.industry = ad.category
  where f.status = 'approved' and p.price > 0
), parsed as (
  select p.id, x.ordinality as ordinal,
    case when x.t->>'min' ~ '^[0-9]{1,10}$' then (x.t->>'min')::numeric end as lo,
    case when x.t->>'max' is null then 2147483647
         when x.t->>'max' ~ '^[0-9]{1,10}$' then (x.t->>'max')::numeric end as hi,
    case when x.t->>'price' ~ '^[0-9]{1,12}([.][0-9]{1,2})?$' then (x.t->>'price')::numeric end as price
  from catalog p cross join lateral jsonb_array_elements(
    case when jsonb_typeof(p.tiers) = 'array' then p.tiers else '[]'::jsonb end
  ) with ordinality x(t, ordinality)
), tiers as (
  select * from parsed where lo between 1 and 2147483647 and hi between lo and 2147483647 and price > 0
), boundaries as (
  select id, lo as qty from tiers union select id, hi + 1 from tiers
  union select id, moq from catalog
), intervals as (
  select id, qty, lead(qty) over (partition by id order by qty) - 1 as last_qty from boundaries
), effective as (
  -- Split overlaps at every boundary; highest minimum wins, as in checkout.
  -- Duplicate minimums with differing prices are ambiguous in legacy checkout: omit them.
  select b.id, b.qty as lo, b.last_qty as hi, chosen.price
  from intervals b join catalog p on p.id = b.id
  cross join lateral (
    select t.price, t.lo from tiers t where t.id = b.id and b.qty between t.lo and t.hi
    order by t.lo desc, t.ordinal desc limit 1
  ) chosen
  where b.qty >= p.moq and b.qty <= 2147483647 and b.last_qty >= b.qty
    and not exists (select 1 from tiers t where t.id = b.id and t.lo = chosen.lo
      and b.qty between t.lo and t.hi and t.price <> chosen.price)
), discounts as (
  select e.*, reference.price as reference_price, reference.lo as reference_min, reference.hi as reference_max,
         trunc((1 - e.price / reference.price) * 100, 1) as discount_percent
  from effective e cross join lateral (
    select r.* from effective r where r.id = e.id and r.lo < e.lo and r.price > e.price
    order by r.price desc, r.lo limit 1
  ) reference
), ranked as (
  select d.*, abs(d.discount_percent - ad.percent) as distance,
    row_number() over (partition by d.id order by abs(d.discount_percent - ad.percent), d.price, d.lo) as choice
  from discounts d cross join promotion ad where d.discount_percent > 0
), selected as (
  select r.*, p.name, p.image, p.images, p.factory_name from ranked r join catalog p on p.id = r.id
  where r.choice = 1
), page as (
  select * from selected order by distance, discount_percent desc, id
  limit least(greatest(coalesce(p_limit, 20), 1), 40) offset greatest(coalesce(p_offset, 0), 0)
)
select jsonb_build_object('category', ad.category, 'percent', ad.percent,
  'has_more', (select count(*) from selected) > greatest(coalesce(p_offset, 0), 0) + least(greatest(coalesce(p_limit, 20), 1), 40),
  'items', coalesce((select jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'image', p.image, 'images', p.images, 'factory_name', p.factory_name,
    'unit_price', p.price, 'min_quantity', p.lo, 'max_quantity', nullif(p.hi, 2147483647),
    'reference_price', p.reference_price, 'reference_min', p.reference_min, 'reference_max', nullif(p.reference_max, 2147483647),
    'discount_percent', p.discount_percent
  ) order by p.distance, p.discount_percent desc, p.id) from page p), '[]'::jsonb))
from promotion ad;
$fn$;
revoke all on function public.get_promotion_quantity_offers(uuid, integer, integer) from public;
grant execute on function public.get_promotion_quantity_offers(uuid, integer, integer) to anon, authenticated;
notify pgrst, 'reload schema';
commit;
