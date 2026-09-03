-- ============================================================
--  وصف المنتج ومواصفاته — 2026-09-03
--
--  جدول products كان يحمل الاسم والسعر والصور فقط، فلا مكان
--  لوصف المنتج ولا لمواصفاته.
--
--  الدالة أدناه نسخة من 20260827181000 مع ثلاث إضافات فقط في
--  كتلة المنتجات — وما عداها منقول حرفياً: القفل المتفائل على
--  updated_at، والتحقق من الملكية، وحدود عدد العناصر.
--  فلا تعد كتابة هذه الدالة من الذاكرة — انسخها من آخر ترحيل
--  يعرّفها ثم عدّل موضع الحاجة وحده.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

-- ---------- 1) الأعمدة ----------
alter table public.products add column if not exists description text not null default '';
alter table public.products add column if not exists material    text not null default '';
alter table public.products add column if not exists sizes       text not null default '';
alter table public.products add column if not exists colors      text not null default '';
alter table public.products add column if not exists moq         integer;

do $guard$
begin
  if not exists (select 1 from pg_constraint where conname = 'products_moq_check') then
    alter table public.products
      add constraint products_moq_check check (moq is null or moq > 0);
  end if;
end
$guard$;


-- ---------- 2) دالة الحفظ ----------
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

    insert into public.products (
      factory_id, client_key, images, image, name, price, sort_order,
      description, material, sizes, colors, moq
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
      clean_moq
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
           moq = excluded.moq
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


-- ============================================================
--  تحقّق: يجب أن تظهر الأعمدة الخمسة الجديدة
-- ============================================================
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'products'
   and column_name in ('description', 'material', 'sizes', 'colors', 'moq')
 order by column_name;
