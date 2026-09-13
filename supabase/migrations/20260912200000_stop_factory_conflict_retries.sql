-- تعارض نسخة المحرّر ليس فشل تسلسل عابرًا؛ PT409 يرجع التعارض دون إعادة تلقائية.
-- نعدّل رمز الخطأ وحده في التعريف الموجود، ونحتفظ بفحص الملكية والطابع الزمني.
begin;
set local lock_timeout = '5s';

do $fix$
declare
  target regprocedure := to_regprocedure('public.save_factory_content(bigint,jsonb,jsonb,jsonb,timestamp with time zone)');
  definition text;
  old_code text := 'errcode = ''40001''';
  new_code text := 'errcode = ''PT409''';
begin
  if target is null then
    raise exception 'Factory save function is missing';
  end if;
  definition := pg_get_functiondef(target);
  if position('Factory data changed in another session; reload before saving' in definition) = 0 then
    raise exception 'Unexpected factory conflict definition; review before changing';
  end if;
  if position(old_code in definition) = 0 and position(new_code in definition) > 0 then
    return;
  end if;
  if (length(definition) - length(replace(definition, old_code, ''))) / length(old_code) <> 1 then
    raise exception 'Expected exactly one factory conflict error code; no changes made';
  end if;
  execute replace(definition, old_code, new_code);
end;
$fix$;

notify pgrst, 'reload schema';
commit;

-- قد تبقى معاملات عالقة بدأت قبل الإصلاح. تُحدّد من process_id في السجل
-- ويُوقف الاتصال المطابق وحده بخطوة منفصلة بعد التحقق منه.
