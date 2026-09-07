-- ============================================================
--  التسعير بالجملة — شرائح كمّية، 2026-09-07
--
--  بطلب المالك مع لقطة مرجعية من علي بابا: سعر المنتج يقلّ
--  كلّما زادت الكمّية، ويحرّر المصنعُ الشرائحَ من صفحته.
--
--  التخزين: عمود jsonb واحد في products لا جدول منفصل.
--  الشرائح قليلة (3-5) وتُقرأ وتُكتب مع المنتج دائماً، فالجدول
--  المستقلّ يضيف سياسات وحذفاً وإدراجاً عند كل حفظ بلا مقابل.
--
--  الشكل:
--    [ { "min": 1,   "max": 50,   "price": 2.20 },
--      { "min": 51,  "max": 100,  "price": 2.00 },
--      { "min": 101, "max": null, "price": 1.70 } ]
--
--  ولماذا الحساب على الخادم:
--  السعر لا يأتي من العميل أبداً — وهو مبدأ create_order_from_cart
--  نفسه. لو حسبه المتصفّح وأرسله، لاشترى أيّ مشتر بريال واحد
--  بتعديل الطلب. فالدالّة تقرأ الشريحة من القاعدة بنفسها.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

-- ------------------------------------------------------------
--  1) العمود
-- ------------------------------------------------------------
alter table public.products
  add column if not exists tiers jsonb not null default '[]'::jsonb;

-- المصفوفة شرط بنيويّ: كائن مفرد أو نصّ يكسر كل قارئ لاحقاً.
alter table public.products
  drop constraint if exists products_tiers_is_array;
alter table public.products
  add constraint products_tiers_is_array
  check (jsonb_typeof(tiers) = 'array');

-- سقف عدد الشرائح: يمنع صفّاً ضخماً يُبطئ كل استعلام منتجات.
alter table public.products
  drop constraint if exists products_tiers_len;
alter table public.products
  add constraint products_tiers_len
  check (jsonb_array_length(tiers) <= 8);


-- ------------------------------------------------------------
--  2) سعر الوحدة عند كمّية معيّنة
--
--  تُرجع سعر أعلى شريحة يشملها العدد، وإلا السعر الأساسي.
--  و«يشملها» تعني min <= qty وكذلك (max is null or qty <= max)،
--  فالشريحة الأخيرة مفتوحة الطرف.
--
--  stable لا volatile: النتيجة ثابتة داخل الاستعلام الواحد،
--  فيستطيع المخطِّط استدعاءها مرّة لكل صفّ لا مرّة لكل مرجع.
-- ------------------------------------------------------------
create or replace function public.tier_unit_price(
  p_product_id bigint,
  p_quantity integer
)
returns numeric
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (
      select (t->>'price')::numeric
        from public.products p,
             lateral jsonb_array_elements(p.tiers) as t
       where p.id = p_product_id
         and (t->>'price') is not null
         and (t->>'price')::numeric > 0
         and p_quantity >= coalesce((t->>'min')::integer, 1)
         and (
              (t->>'max') is null
           or p_quantity <= (t->>'max')::integer
         )
       order by coalesce((t->>'min')::integer, 1) desc
       limit 1
    ),
    (select price from public.products where id = p_product_id)
  );
$fn$;

revoke all on function public.tier_unit_price(bigint, integer) from public, anon;
grant execute on function public.tier_unit_price(bigint, integer) to authenticated, anon;


-- ------------------------------------------------------------
--  3) إنشاء الطلب — الشريحة تدخل في ترتيب الأسعار
--
--  الترتيب: سعر خاصّ بالعميل ← سعر الشريحة ← السعر الأساسي.
--  والسعر الخاصّ يبقى أعلى الجميع: هو اتّفاق بين الطرفين على
--  هذا المشتري بعينه، فلا تنقضه شريحة عامّة.
--
--  وما عدا ذلك فالدالّة كما كانت: لا تقبل مبلغاً من العميل،
--  وتحسب الضريبة والتوصيل والرسوم بالمعادلة نفسها.
-- ------------------------------------------------------------
create or replace function public.create_order_from_cart(
  p_factory_id bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $fn$
declare
  cart_row public.carts%rowtype;
  result_row public.orders%rowtype;
  subtotal_value numeric(14,2);
  shipping_value numeric(14,2) := 30;
  fee_rate_value numeric(5,4) := 0.01;
  fee_value numeric(14,2);
  taxable_value numeric(14,2);
  vat_rate_value numeric(5,4) := 0.15;
  vat_value numeric(14,2);
  total_value numeric(14,2);
  item_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_factory_id is null then raise exception 'Factory is required' using errcode = '22023'; end if;

  select * into cart_row from public.carts where owner_id = auth.uid() for update;
  if not found then raise exception 'Cart is empty' using errcode = '22023'; end if;

  select count(*), coalesce(sum(
    ci.quantity * coalesce(
      cp.price,
      public.tier_unit_price(p.id, ci.quantity),
      p.price
    )
  ), 0)
    into item_count, subtotal_value
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id and p.factory_id = p_factory_id;

  if item_count = 0 then raise exception 'Cart has no products for this factory' using errcode = '22023'; end if;
  if exists (
    select 1 from public.cart_items ci join public.products p on p.id = ci.product_id
     where ci.cart_id = cart_row.id and p.factory_id <> p_factory_id
  ) then
    raise exception 'Create one order per factory' using errcode = '22023';
  end if;

  fee_value := round((subtotal_value + shipping_value) * fee_rate_value, 2);

  taxable_value := subtotal_value + shipping_value + fee_value;
  vat_value := round(taxable_value * vat_rate_value, 2);
  total_value := taxable_value + vat_value;

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, shipping, payment_fee,
    vat_rate, vat_amount, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_payment', subtotal_value,
    shipping_value, fee_value, vat_rate_value, vat_value, total_value,
    p_idempotency_key
  ) on conflict (buyer_id, idempotency_key) do update
    set updated_at = excluded.updated_at
  returning * into result_row;

  insert into public.order_items (
    order_id, product_id, product_name, unit_price, quantity, line_total
  )
  select result_row.id, p.id, p.name,
         coalesce(cp.price, public.tier_unit_price(p.id, ci.quantity), p.price),
         ci.quantity,
         coalesce(cp.price, public.tier_unit_price(p.id, ci.quantity), p.price) * ci.quantity
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id;

  delete from public.cart_items where cart_id = cart_row.id;
  return result_row;
end;
$fn$;

revoke all on function public.create_order_from_cart(bigint, uuid)
  from public, anon;
grant execute on function public.create_order_from_cart(bigint, uuid)
  to authenticated;


-- ------------------------------------------------------------
--  4) الحفظ من صفحة المصنع
--
--  save_factory_content تكتب المنتجات حذفاً ثمّ إدراجاً، وهي
--  التي يمرّ عبرها تحرير المالك. والصلاحية محسومة هناك أصلاً:
--  الدالّة تتحقّق من ملكية المصنع قبل الكتابة، فالشرائح تدخل
--  في الحماية نفسها بلا سياسة جديدة.
--
--  وسياسات products كما هي: القراءة للجميع، والكتابة لمالك
--  المصنع وحده — وهو ما طلبه المالك (لا صلاحية للمشرف هنا).
-- ------------------------------------------------------------

-- ------------------------------------------------------------
--  5) دالّة الحفظ — الشرائح تمرّ مع المنتج
--
--  منسوخة من 20260903110000 حرفياً مع إضافة tiers وحدها —
--  وذلك ما يأمر به تعليق ذلك الملفّ: لا تُعاد كتابة
--  هذه الدالّة من الذاكرة، ففيها قفل متفائل وتحقّق ملكية
--  وحدود عدد، وإغفال أحدها ثغرة لا تُرى.
--
--  والتنقية في الخادم لا في المتصفّح: العميل يرسل ما
--  يشاء، فشريحة بسعر سالب أو مدى مقلوب تُرفض هنا.
-- ------------------------------------------------------------
create or replace function public.save_factory_content(
  p_factory_id bigint,
  p_factory jsonb,
  p_products jsonb default null,
  p_posts jsonb default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  current_row public.factories%rowtype;
  item jsonb;
  item_key uuid;
  product_keys uuid[] := '{}';
  post_keys uuid[] := '{}';
  clean_images text[];
  clean_price numeric(12, 2);
  clean_moq integer;
  clean_tiers jsonb;
  result_row jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if jsonb_typeof(coalesce(p_factory, '{}'::jsonb)) <> 'object'
     or (p_products is not null and jsonb_typeof(p_products) <> 'array')
     or (p_posts is not null and jsonb_typeof(p_posts) <> 'array') then
    raise exception 'Invalid factory payload' using errcode = '22023';
  end if;

  if (p_products is not null and jsonb_array_length(p_products) > 200)
     or (p_posts is not null and jsonb_array_length(p_posts) > 500) then
    raise exception 'Payload exceeds allowed item count' using errcode = '22023';
  end if;

  -- Serialize edits for one factory and lock the owner row.
  perform pg_advisory_xact_lock(p_factory_id);
  select * into current_row
    from public.factories
   where id = p_factory_id
     and owner_id = auth.uid()
   for update;

  if not found then
    raise exception 'Factory not found or not owned by current user'
      using errcode = '42501';
  end if;

  if p_expected_updated_at is not null
     and current_row.updated_at is distinct from p_expected_updated_at then
    raise exception 'Factory data changed in another session; reload before saving'
      using errcode = '40001';
  end if;

  if coalesce(p_factory->>'website', '') <> ''
     and coalesce(p_factory->>'website', '') !~* '^https?://[^[:space:]]+$' then
    raise exception 'Website must use http or https' using errcode = '22023';
  end if;

  update public.factories
     set name = case when p_factory ? 'name' then left(coalesce(p_factory->>'name', ''), 200) else current_row.name end,
         about = case when p_factory ? 'about' then left(coalesce(p_factory->>'about', ''), 10000) else current_row.about end,
         cover = case when p_factory ? 'cover' then left(coalesce(p_factory->>'cover', ''), 2048) else current_row.cover end,
         logo = case when p_factory ? 'logo' then left(coalesce(p_factory->>'logo', ''), 2048) else current_row.logo end,
         website = case when p_factory ? 'website' then left(coalesce(p_factory->>'website', ''), 2048) else current_row.website end,
         industry = case when p_factory ? 'industry' then left(coalesce(p_factory->>'industry', ''), 200) else current_row.industry end,
         company_size = case when p_factory ? 'company_size' then left(coalesce(p_factory->>'company_size', ''), 100) else current_row.company_size end
   where id = p_factory_id;

  -- Upsert products by stable client_key. NULL means “leave unchanged”.
  if p_products is not null then
  for item in select value from jsonb_array_elements(p_products) loop
    begin
      item_key := nullif(item->>'client_key', '')::uuid;
    exception when invalid_text_representation then
      item_key := null;
    end;

    if item_key is null
       or exists (
         select 1 from public.products p
          where p.client_key = item_key and p.factory_id <> p_factory_id
       ) then
      item_key := gen_random_uuid();
    end if;

    select coalesce(array_agg(left(value, 2048)), '{}')
      into clean_images
      from (
        select value
          from jsonb_array_elements_text(
            case when jsonb_typeof(item->'images') = 'array'
                 then item->'images' else '[]'::jsonb end
          )
         where value <> ''
         limit 5
      ) image_values;

    if coalesce(item->>'price', '') ~ '^[0-9]+([.][0-9]{1,2})?$' then
      clean_price := (item->>'price')::numeric(12, 2);
    else
      clean_price := null;
    end if;

    -- MOQ: عدد صحيح موجب وإلا NULL. الحدّ الأعلى يمنع فيضاناً
    -- يرفع خطأ يُفشل الحفظ كلّه.
    if coalesce(item->>'moq', '') ~ '^[0-9]+$'
       and (item->>'moq')::numeric between 1 and 2147483647 then
      clean_moq := (item->>'moq')::integer;
    else
      clean_moq := null;
    end if;

    -- الشرائح: تُقبل مصفوفة فقط، وتُصفّى إلى عناصر
    -- صالحة: min عدد موجب، وprice رقم موجب، وmax إمّا
    -- فارغ (فما فوق) أو عدد لا يقلّ عن min.
    -- التنقية هنا لا في المتصفّح: العميل يرسل ما يشاء.
    if jsonb_typeof(item->'tiers') = 'array' then
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'min',   (t->>'min')::integer,
                 'max',   case when (t->>'max') is null then null
                               else (t->>'max')::integer end,
                 'price', round((t->>'price')::numeric, 2)
               ) order by (t->>'min')::integer
             ), '[]'::jsonb)
        into clean_tiers
        from (
          select value as t
            from jsonb_array_elements(item->'tiers')
           limit 8
        ) raw_tiers
       where (t->>'min') ~ '^[0-9]+$'
         and (t->>'min')::numeric between 1 and 2147483647
         and (t->>'price') ~ '^[0-9]+([.][0-9]{1,2})?$'
         and (t->>'price')::numeric > 0
         and (
              (t->>'max') is null
           or (    (t->>'max') ~ '^[0-9]+$'
               and (t->>'max')::numeric between 1 and 2147483647
               and (t->>'max')::integer >= (t->>'min')::integer)
         );
    else
      clean_tiers := '[]'::jsonb;
    end if;

    insert into public.products (
      factory_id, client_key, images, image, name, price, sort_order,
      description, material, sizes, colors, moq, tiers
    ) values (
      p_factory_id,
      item_key,
      clean_images,
      coalesce(clean_images[1], ''),
      left(coalesce(item->>'name', ''), 300),
      clean_price,
      coalesce(array_length(product_keys, 1), 0),
      left(coalesce(item->>'description', ''), 2000),
      left(coalesce(item->>'material', ''), 120),
      left(coalesce(item->>'sizes', ''), 120),
      left(coalesce(item->>'colors', ''), 120),
      clean_moq,
      clean_tiers
    )
    on conflict (client_key) do update
       set images = excluded.images,
           image = excluded.image,
           name = excluded.name,
           price = excluded.price,
           sort_order = excluded.sort_order,
           description = excluded.description,
           material = excluded.material,
           sizes = excluded.sizes,
           colors = excluded.colors,
           moq = excluded.moq,
           tiers = excluded.tiers
     where products.factory_id = p_factory_id;

    product_keys := array_append(product_keys, item_key);
  end loop;

  delete from public.products
   where factory_id = p_factory_id
     and not (client_key = any(product_keys));
  end if;

  -- Upsert posts by stable client_key. NULL means “leave unchanged”.
  if p_posts is not null then
  for item in select value from jsonb_array_elements(p_posts) loop
    begin
      item_key := nullif(item->>'client_key', '')::uuid;
    exception when invalid_text_representation then
      item_key := null;
    end;

    if item_key is null
       or exists (
         select 1 from public.posts p
          where p.client_key = item_key and p.factory_id <> p_factory_id
       ) then
      item_key := gen_random_uuid();
    end if;

    insert into public.posts (
      factory_id, client_key, body, image, video
    ) values (
      p_factory_id,
      item_key,
      left(coalesce(item->>'body', ''), 10000),
      left(coalesce(item->>'image', ''), 2048),
      left(coalesce(item->>'video', ''), 2048)
    )
    on conflict (client_key) do update
       set body = excluded.body,
           image = excluded.image,
           video = excluded.video
     where posts.factory_id = p_factory_id;

    post_keys := array_append(post_keys, item_key);
  end loop;

  delete from public.posts
   where factory_id = p_factory_id
     and not (client_key = any(post_keys));
  end if;

  select jsonb_build_object(
    'factory', to_jsonb(f),
    'products', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.sort_order)
        from public.products p where p.factory_id = p_factory_id
    ), '[]'::jsonb),
    'posts', coalesce((
      select jsonb_agg(to_jsonb(po) order by po.created_at desc)
        from public.posts po where po.factory_id = p_factory_id
    ), '[]'::jsonb)
  ) into result_row
  from public.factories f
  where f.id = p_factory_id;

  return result_row;
end;
$fn$;


-- تحقّق أخير يُطبع بعد التشغيل
select 'tiers column + tier_unit_price installed' as status;
