-- ============================================================
-- بطاقة منتج في المحادثة (بطلب المالك)
-- ------------------------------------------------------------
-- كان الاستفسار وطلب السعر يُرسلان نصّاً يحمل اسم المنتج،
-- فوصلت المصنع رسالة «استفسار عن: <اسم المصنع>» ولا يعرف
-- أيّ منتجاته يُسأل عنه — رصده المالك، وأرى صورة عليّ بابا:
-- تصل بطاقة فيها صورة المنتج واسمه وسعره وحدّه الأدنى.
--
-- والجدول لا يحمل ما يُعرّف المنتج: body وattachment_url
-- وattachment_type وحدها، وقيدها يرفض غير image/video.
-- فيُضاف عمود، ويُوسّع القيد.
--
-- يُطبَّق مرّة واحدة:
-- Supabase → SQL Editor → New query → لصق → Run
-- ============================================================

-- 1) عمود المنتج -----------------------------------------------
-- on delete set null لا cascade: حذف منتج لا يمحو رسائل
-- المحادثة، فتبقى المراسلة وتفقد بطاقتها وحدها.
alter table public.messages
  add column if not exists product_id bigint
    references public.products(id) on delete set null;

-- 2) توسيع قيد النوع ------------------------------------------
-- الاسم مأخوذ من تسمية بوستجرس التلقائية في schema.sql.
alter table public.messages
  drop constraint if exists messages_attachment_type_check;

alter table public.messages
  add constraint messages_attachment_type_check
    check (attachment_type in ('', 'image', 'video', 'product'));

-- 3) بطاقة بلا منتج لا معنى لها -------------------------------
-- القيد يمنع رسالة نوعها product وعمودها فارغ، فلا تصل
-- المصنع بطاقة جوفاء لا يعرف ماذا فيها.
alter table public.messages
  drop constraint if exists messages_product_card_check;

alter table public.messages
  add constraint messages_product_card_check
    check (attachment_type <> 'product' or product_id is not null);

-- 4) قراءة المنتج مع الرسالة ----------------------------------
-- المشتري يراسل مصنعاً لا يملكه، فقراءة products مباشرةً
-- من الواجهة تخضع لـRLS — وهي تسمح بالمعتمد وحده. والبطاقة
-- قد تشير إلى منتج مصنعٍ لم يُعتمد بعد، فتصل بلا صورة ولا اسم.
--
-- فدالّة security definer تُرجع ما تحتاجه البطاقة وحده،
-- ولا تُرجعه إلا لطرف في المحادثة — يتحقّق منه داخلها.
create or replace function public.get_message_products(
  p_conversation_id bigint
) returns table (
  product_id bigint,
  name       text,
  image      text,
  price      numeric,
  tiers      jsonb,
  moq        integer
)
language sql
stable
security definer
set search_path = public
as $fn$
  select p.id,
         coalesce(p.name, ''),
         /* رابط Storage وحده: القيم القديمة قد تحمل base64
            مقصوصاً عند 2048 حرفاً فلا يعرضه المتصفّح. */
         coalesce(
           (select u from unnest(coalesce(p.images, array[]::text[])) as u
             where u like 'http%' limit 1),
           case when p.image like 'http%' then p.image else '' end),
         p.price,
         coalesce(p.tiers, '[]'::jsonb),
         p.moq
    from public.messages m
    join public.products p on p.id = m.product_id
   where m.conversation_id = p_conversation_id
     and m.product_id is not null
     /* طرف المحادثة وحده يقرأ: غيره يحصل على صفر صفوف.
        والفرد في individual_id، وصاحب المصنع يُوصَل إليه
        عبر factories.owner_id — لا عمود مباشر له. */
     and exists (
       select 1
         from public.conversations c
         join public.factories f on f.id = c.factory_id
        where c.id = p_conversation_id
          and (c.individual_id = auth.uid() or f.owner_id = auth.uid())
     )
   group by p.id, p.name, p.image, p.images, p.price, p.tiers, p.moq;
$fn$;

revoke all on function public.get_message_products(bigint) from public;
grant execute on function public.get_message_products(bigint) to authenticated;

-- 5) تحقّق ---------------------------------------------------
select 'product card messages ready' as status;
