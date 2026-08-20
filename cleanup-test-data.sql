-- ============================================================
--  حذف حسابات الاختبار
--  أُنشئت أثناء التحقق من الحماية — بريدها ينتهي بـ example.com
--  الحذف يمتد تلقائيًا إلى profiles و factories (on delete cascade)
-- ============================================================

delete from auth.users where email like '%@example.com';

-- احتياط: إعادة أي بقايا إلى الحالة الآمنة
update public.factories set status = 'pending' where status = 'approved';
update public.profiles  set is_admin = false    where is_admin = true;
