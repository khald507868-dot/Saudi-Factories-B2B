-- لقطة للقراءة فقط؛ لا توقف اتصالات ولا تغيّر إعدادات أو بيانات.
-- لا تعرض نصوص الاستعلامات أو عناوين العملاء أو رموز الدخول.
begin read only;
set local search_path = pg_catalog, extensions, public;

with activity as (
  select pid, usename, application_name, backend_type, state,
         wait_event_type, wait_event, query_id,
         round(extract(epoch from (statement_timestamp() - backend_start))::numeric, 1) as connection_age_seconds,
         case when state = 'active' then
           round(extract(epoch from (statement_timestamp() - query_start))::numeric, 3)
         end as active_query_age_seconds,
         case
           when query ilike '%realtime.list_changes%' then 'realtime_list_changes'
           when query ilike '%realtime.apply_rls%' then 'realtime_apply_rls'
           when query ilike '%START_REPLICATION%' then 'replication_stream'
           when query ilike '%set_config%' and query ilike '%request.jwt.claims%' then 'request_settings'
           when query is null then 'not_visible'
           else 'other'
         end as query_category
    from pg_stat_activity
   where pid <> pg_backend_pid()
     and (datname = current_database() or datname is null)
), slots as (
  select slot_name, plugin, slot_type, active, active_pid,
         pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as retained_wal_bytes,
         pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as unconfirmed_wal_bytes
    from pg_replication_slots
   where database = current_database()
)
select statement_timestamp() as sampled_at,
       'connection' as item_type, to_jsonb(a) as details
  from activity a
union all
select statement_timestamp(), 'replication_slot', to_jsonb(s)
  from slots s
order by item_type;

commit;
