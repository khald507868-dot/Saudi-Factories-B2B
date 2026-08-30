-- One fast, safe total for the messages icon badge.

create or replace function public.get_unread_message_total()
returns bigint
language sql
security definer
set search_path = public
stable
as $fn$
  select count(*)
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
    join public.factories f on f.id = c.factory_id
   where m.sender_id <> auth.uid()
     and m.read_at is null
     and (
       c.individual_id = auth.uid()
       or f.owner_id = auth.uid()
     );
$fn$;

revoke all on function public.get_unread_message_total() from public;
grant execute on function public.get_unread_message_total() to authenticated;
