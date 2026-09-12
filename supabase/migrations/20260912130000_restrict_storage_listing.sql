-- الخطوة الأولى من مراجعة Security Advisor بتاريخ 12 سبتمبر 2026.
-- عرض الصور والمقاطع العامة بروابطها يستمر؛ نقيّد استعراض سجلات الملفات فقط.
-- تُطبّق بعد المهاجرات السابقة، ويمكن إعادة تشغيلها دون حذف ملفات أو بيانات.
begin;

drop policy if exists factory_media_public_read on storage.objects;
drop policy if exists factory_media_owner_read on storage.objects;
create policy factory_media_owner_read on storage.objects
  for select to authenticated using (
    bucket_id = 'factory-media'
    and (
      owner_id = (select auth.uid())::text
      or (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.is_admin())
    )
  );

drop policy if exists promotion_media_read on storage.objects;
create policy promotion_media_read on storage.objects
  for select to authenticated using (
    bucket_id = 'promotion-media' and (select public.is_admin())
  );

drop policy if exists video_promotion_media_read on storage.objects;
create policy video_promotion_media_read on storage.objects
  for select to authenticated using (
    bucket_id = 'video-promotion-media' and (select public.is_admin())
  );

-- يمنع أي سياسة SELECT أو ALL واسعة من إعادة كشف القائمة لهذه الحاويات.
-- لا يغيّر صلاحيات المحادثات أو الحاويات الأخرى.
drop policy if exists public_media_listing_guard on storage.objects;
create policy public_media_listing_guard on storage.objects
  as restrictive for select to public using (
    bucket_id not in ('factory-media', 'promotion-media', 'video-promotion-media')
    or (
      (select auth.uid()) is not null
      and (
        (select public.is_admin())
        or (
          bucket_id = 'factory-media'
          and (
            owner_id = (select auth.uid())::text
            or (storage.foldername(name))[1] = (select auth.uid())::text
          )
        )
      )
    )
  );

commit;
