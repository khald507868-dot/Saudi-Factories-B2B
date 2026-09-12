-- ربط بطاقة المنتج بمصنع المحادثة، ومنع استبدال المنتج في رسالة موجودة.
-- يعتمد على ترحيل product_card_messages وترحيل restrict_internal_functions.
begin;

create or replace function public.guard_message_insert()
returns trigger
language plpgsql security definer set search_path = public
as $fn$
begin
  if auth.uid() is null or new.sender_id is distinct from auth.uid()
     or not public.in_conversation(new.conversation_id) then
    raise exception 'Message access denied' using errcode = '42501';
  end if;
  if length(coalesce(new.body, '')) > 10000 then
    raise exception 'Message body is too long' using errcode = '22023';
  end if;

  if new.product_id is not null then
    if not exists (
      select 1 from public.products p
      join public.conversations c on c.factory_id = p.factory_id
      where p.id = new.product_id and c.id = new.conversation_id
    ) then
      raise exception 'Product is not available in this conversation' using errcode = '42501';
    end if;
    if coalesce(new.attachment_url, '') <> ''
       or coalesce(new.attachment_type, '') not in ('', 'product') then
      raise exception 'Product card cannot contain another attachment' using errcode = '22023';
    end if;
    new.attachment_url := '';
    new.attachment_type := 'product';
  else
    if new.attachment_type = 'product' then
      raise exception 'Product card requires a product' using errcode = '22023';
    end if;
    if coalesce(new.attachment_url, '') = '' then
      new.attachment_url := '';
      new.attachment_type := '';
    elsif position(new.sender_id::text || '/' in new.attachment_url) <> 1 then
      raise exception 'Attachment path is not owned by sender' using errcode = '42501';
    elsif new.attachment_type is null or new.attachment_type not in ('image', 'video') then
      raise exception 'Invalid attachment type' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$fn$;

create or replace function public.guard_message_columns()
returns trigger
language plpgsql security definer set search_path = public
as $fn$
begin
  new.id := old.id;
  new.conversation_id := old.conversation_id;
  new.sender_id := old.sender_id;
  new.body := old.body;
  new.created_at := old.created_at;
  new.attachment_url := old.attachment_url;
  new.attachment_type := old.attachment_type;
  new.custom_price_id := old.custom_price_id;
  new.client_key := old.client_key;

  -- الاستثناء لإجراء المفتاح الخارجي ON DELETE SET NULL عند حذف المنتج نفسه.
  -- لا يستطيع العميل إزالة ارتباط منتج ما زال موجوداً أو تغييره إلى منتج آخر.
  if old.product_id is not null and new.product_id is null
     and not exists (select 1 from public.products where id = old.product_id) then
    new.attachment_type := '';
  else
    new.product_id := old.product_id;
  end if;
  return new;
end;
$fn$;

create or replace function public.get_message_products(p_conversation_id bigint)
returns table(product_id bigint, name text, image text, price numeric, tiers jsonb, moq integer)
language sql stable security definer set search_path = public
as $fn$
  select p.id,
         coalesce(p.name, ''),
         coalesce(
           (select u from unnest(coalesce(p.images, array[]::text[])) as u
             where u like 'http%' limit 1),
           case when p.image like 'http%' then p.image else '' end),
         p.price,
         coalesce(p.tiers, '[]'::jsonb),
         p.moq
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
    join public.factories f on f.id = c.factory_id
    join public.products p on p.id = m.product_id and p.factory_id = c.factory_id
   where c.id = p_conversation_id
     and (c.individual_id = auth.uid() or f.owner_id = auth.uid())
   group by p.id, p.name, p.image, p.images, p.price, p.tiers, p.moq;
$fn$;

-- الاحتفاظ بتضييق الصلاحيات المنفذ في الخطوة السابقة حتى على تثبيت جديد.
revoke execute on function public.guard_message_insert() from public, anon, authenticated;
revoke execute on function public.guard_message_columns() from public, anon, authenticated;
revoke execute on function public.get_message_products(bigint) from public, anon;
grant execute on function public.get_message_products(bigint) to authenticated;

notify pgrst, 'reload schema';
commit;
