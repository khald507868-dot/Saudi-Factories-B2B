-- ============================================================
--  فحص أمني: هل عاد حارس المصانع مفعّلاً؟
--
--  الحارس factories_guard يمنع أي مصنع من اعتماد نفسه.
--  عطّلناه لثانية أثناء الاعتماد، والملف يعيد تفعيله —
--  لكن التأكد واجب: تركه معطّلاً يعني أن أي مصنع يستطيع
--  اعتماد نفسه، فتصير مراجعة الإدارة بلا معنى.
--
--  الخطوات: Supabase ← SQL Editor ← New query ← لصق ← Run
--
--  المطلوب أن ترى:  tgenabled = O   ومعناها مفعّل (Origin)
--  لو رأيت:         tgenabled = D   ومعناها معطّل (Disabled)
--                   ← عندها شغّل السطر الأخير في هذا الملف
-- ============================================================

select tgname          as trigger_name,
       tgenabled       as state,
       case tgenabled
         when 'O' then 'مفعّل — سليم'
         when 'D' then 'معطّل — خطر! فعّله فوراً'
         else 'حالة أخرى'
       end             as meaning
from pg_trigger
where tgrelid = 'public.factories'::regclass
  and not tgisinternal
order by tgname;


-- إن ظهر D أمام factories_guard، احذف العلامتين -- من
-- السطر التالي ثم شغّل الملف مرة أخرى:

-- alter table public.factories enable trigger factories_guard;
