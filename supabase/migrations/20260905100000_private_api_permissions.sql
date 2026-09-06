-- Keep account-scoped RPCs out of the anonymous PostgREST surface.
--
-- Supabase projects can have default privileges that grant EXECUTE directly
-- to `anon`.  Revoking from PostgreSQL's pseudo-role PUBLIC alone does not
-- remove that explicit grant, so anonymous callers could still reach these
-- functions (the functions' auth.uid() checks prevented writes, but the API
-- permissions did not match the intended authenticated-only contract).

revoke all on function public.save_factory_content(bigint, jsonb, jsonb, jsonb, timestamptz)
  from public, anon;
revoke all on function public.get_or_create_cart()
  from public, anon;
revoke all on function public.add_to_cart(bigint, numeric)
  from public, anon;
revoke all on function public.create_order_from_cart(bigint, uuid)
  from public, anon;
revoke all on function public.get_conversation_peers()
  from public, anon;
revoke all on function public.get_conversation_summaries()
  from public, anon;
revoke all on function public.mark_conversation_read(bigint)
  from public, anon;
revoke all on function public.get_unread_message_total()
  from public, anon;

grant execute on function public.save_factory_content(bigint, jsonb, jsonb, jsonb, timestamptz)
  to authenticated;
grant execute on function public.get_or_create_cart()
  to authenticated;
grant execute on function public.add_to_cart(bigint, numeric)
  to authenticated;
grant execute on function public.create_order_from_cart(bigint, uuid)
  to authenticated;
grant execute on function public.get_conversation_peers()
  to authenticated;
grant execute on function public.get_conversation_summaries()
  to authenticated;
grant execute on function public.mark_conversation_read(bigint)
  to authenticated;
grant execute on function public.get_unread_message_total()
  to authenticated;

-- Favorites are account-private and are never used before authentication.
-- Grant only the operations used by favorites-service.js.
revoke all on table public.favorites from public, anon;
revoke all on sequence public.favorites_id_seq from public, anon;
grant select, insert, delete on table public.favorites to authenticated;
grant usage, select on sequence public.favorites_id_seq to authenticated;
