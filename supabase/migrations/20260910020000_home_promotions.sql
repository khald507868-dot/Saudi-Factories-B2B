-- إعلانات تخفيضات الرئيسية: الجميع يرى المنشور، والمدير وحده يدير المحتوى.
-- قابل لإعادة التشغيل؛ يُطبّق بعد schema.sql والمهاجرات السابقة.
begin;

create table if not exists public.home_promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  image_url text not null check (
    char_length(image_url) <= 2048
    and image_url ~ '^https://[^/[:space:]?#]+/storage/v1/object/public/promotion-media/[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$'
  ),
  target_url text not null default '' check (
    char_length(target_url) <= 2048
    and (target_url = '' or target_url ~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$')
  ),
  is_active boolean not null default true,
  sort_order integer not null default 0 check (sort_order between 0 and 9999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists home_promotions_display_idx
  on public.home_promotions (is_active, sort_order, created_at, id);

alter table public.home_promotions enable row level security;
grant select on public.home_promotions to anon, authenticated;
grant insert, update, delete on public.home_promotions to authenticated;
revoke insert, update, delete on public.home_promotions from anon;

drop policy if exists home_promotions_read on public.home_promotions;
create policy home_promotions_read on public.home_promotions
  for select to anon, authenticated
  using (is_active or public.is_admin());

drop policy if exists home_promotions_insert_admin on public.home_promotions;
create policy home_promotions_insert_admin on public.home_promotions
  for insert to authenticated with check (public.is_admin());

drop policy if exists home_promotions_update_admin on public.home_promotions;
create policy home_promotions_update_admin on public.home_promotions
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists home_promotions_delete_admin on public.home_promotions;
create policy home_promotions_delete_admin on public.home_promotions
  for delete to authenticated using (public.is_admin());

drop trigger if exists home_promotions_touch on public.home_promotions;
create trigger home_promotions_touch before update on public.home_promotions
  for each row execute function public.touch_updated_at();

-- الصور إعلانية عامة، وإخفاء الإعلان يوقف ظهوره في القائمة لا صلاحية الرابط.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'promotion-media', 'promotion-media', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists promotion_media_read on storage.objects;
create policy promotion_media_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'promotion-media');

drop policy if exists promotion_media_admin_insert on storage.objects;
create policy promotion_media_admin_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'promotion-media'
    and public.is_admin()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists promotion_media_admin_delete on storage.objects;
create policy promotion_media_admin_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'promotion-media'
    and public.is_admin()
    and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (
      select 1 from public.home_promotions p
      where substring(p.image_url from '/storage/v1/object/public/promotion-media/(.*)$') = name
    )
  );

-- السياسات المقيّدة تمنع سياسات عامة سابقة من توسيع صلاحيات هذا الدلو.
-- الصور immutable: التعديل يرفع ملفاً جديداً، حتى لا تتبدّل صورة إعلان آخر.
drop policy if exists promotion_media_guard_insert on storage.objects;
create policy promotion_media_guard_insert on storage.objects
  as restrictive for insert to public with check (
    bucket_id <> 'promotion-media'
    or (
      public.is_admin()
      and (storage.foldername(name))[1] = auth.uid()::text
    )
  );

drop policy if exists promotion_media_guard_update on storage.objects;
create policy promotion_media_guard_update on storage.objects
  as restrictive for update to public
  using (bucket_id <> 'promotion-media')
  with check (bucket_id <> 'promotion-media');

drop policy if exists promotion_media_guard_delete on storage.objects;
create policy promotion_media_guard_delete on storage.objects
  as restrictive for delete to public using (
    bucket_id <> 'promotion-media'
    or (
      public.is_admin()
      and (storage.foldername(name))[1] = auth.uid()::text
      and not exists (
        select 1 from public.home_promotions p
        where substring(p.image_url from '/storage/v1/object/public/promotion-media/(.*)$') = name
      )
    )
  );

notify pgrst, 'reload schema';
commit;
