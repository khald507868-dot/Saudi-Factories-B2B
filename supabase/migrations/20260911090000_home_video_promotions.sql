-- إعلانات الفيديو بين الفئات والمنتجات: الجميع يرى المنشور، والمدير وحده يدير المحتوى.
-- قابل لإعادة التشغيل؛ يُطبّق بعد schema.sql والمهاجرات السابقة.
begin;

create table if not exists public.home_video_promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  image_url text not null check (
    char_length(image_url) <= 2048
    and image_url ~ '^https://[^/[:space:]?#]+/storage/v1/object/public/video-promotion-media/[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$'
  ),
  video_url text not null check (
    char_length(video_url) <= 2048
    and video_url ~ '^https://[^/[:space:]?#]+/storage/v1/object/public/video-promotion-media/[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(mp4|webm|mov)$'
  ),
  logo_url text not null default '' check (logo_url = '' or (
    char_length(logo_url) <= 2048
    and logo_url ~ '^https://[^/[:space:]?#]+/storage/v1/object/public/video-promotion-media/[0-9a-fA-F-]{36}/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$'
  )),
  target_url text not null default '' check (
    char_length(target_url) <= 2048
    and (target_url = '' or target_url ~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$')
  ),
  is_active boolean not null default true,
  sort_order integer not null default 0 check (sort_order between 0 and 9999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists home_video_promotions_display_idx
  on public.home_video_promotions (is_active, sort_order, created_at, id);

alter table public.home_video_promotions enable row level security;
grant select on public.home_video_promotions to anon, authenticated;
grant insert, update, delete on public.home_video_promotions to authenticated;
revoke insert, update, delete on public.home_video_promotions from anon;

drop policy if exists home_video_promotions_read on public.home_video_promotions;
create policy home_video_promotions_read on public.home_video_promotions
  for select to anon, authenticated
  using (is_active or public.is_admin());

drop policy if exists home_video_promotions_insert_admin on public.home_video_promotions;
create policy home_video_promotions_insert_admin on public.home_video_promotions
  for insert to authenticated with check (public.is_admin());

drop policy if exists home_video_promotions_update_admin on public.home_video_promotions;
create policy home_video_promotions_update_admin on public.home_video_promotions
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists home_video_promotions_delete_admin on public.home_video_promotions;
create policy home_video_promotions_delete_admin on public.home_video_promotions
  for delete to authenticated using (public.is_admin());

drop trigger if exists home_video_promotions_touch on public.home_video_promotions;
create trigger home_video_promotions_touch before update on public.home_video_promotions
  for each row execute function public.touch_updated_at();

-- الوسائط إعلانية عامة، وإخفاء الإعلان يوقف ظهوره في القائمة لا صلاحية الرابط.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'video-promotion-media', 'video-promotion-media', true, 52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/webm', 'video/quicktime']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists video_promotion_media_read on storage.objects;
create policy video_promotion_media_read on storage.objects
  for select to anon, authenticated using (bucket_id = 'video-promotion-media');

drop policy if exists video_promotion_media_admin_insert on storage.objects;
create policy video_promotion_media_admin_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'video-promotion-media'
    and public.is_admin()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists video_promotion_media_admin_delete on storage.objects;
create policy video_promotion_media_admin_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'video-promotion-media'
    and public.is_admin()
    and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (
      select 1 from public.home_video_promotions p
      where name in (substring(p.image_url from '/storage/v1/object/public/video-promotion-media/(.*)$'), substring(p.video_url from '/storage/v1/object/public/video-promotion-media/(.*)$'), substring(p.logo_url from '/storage/v1/object/public/video-promotion-media/(.*)$'))
    )
  );

-- السياسات المقيّدة تمنع سياسات عامة سابقة من توسيع صلاحيات هذا الدلو.
-- الصور immutable: التعديل يرفع ملفاً جديداً، حتى لا تتبدّل صورة إعلان آخر.
drop policy if exists video_promotion_media_guard_insert on storage.objects;
create policy video_promotion_media_guard_insert on storage.objects
  as restrictive for insert to public with check (
    bucket_id <> 'video-promotion-media'
    or (
      public.is_admin()
      and (storage.foldername(name))[1] = auth.uid()::text
    )
  );

drop policy if exists video_promotion_media_guard_update on storage.objects;
create policy video_promotion_media_guard_update on storage.objects
  as restrictive for update to public
  using (bucket_id <> 'video-promotion-media')
  with check (bucket_id <> 'video-promotion-media');

drop policy if exists video_promotion_media_guard_delete on storage.objects;
create policy video_promotion_media_guard_delete on storage.objects
  as restrictive for delete to public using (
    bucket_id <> 'video-promotion-media'
    or (
      public.is_admin()
      and (storage.foldername(name))[1] = auth.uid()::text
      and not exists (
        select 1 from public.home_video_promotions p
        where name in (substring(p.image_url from '/storage/v1/object/public/video-promotion-media/(.*)$'), substring(p.video_url from '/storage/v1/object/public/video-promotion-media/(.*)$'), substring(p.logo_url from '/storage/v1/object/public/video-promotion-media/(.*)$'))
      )
    )
  );

notify pgrst, 'reload schema';
commit;
