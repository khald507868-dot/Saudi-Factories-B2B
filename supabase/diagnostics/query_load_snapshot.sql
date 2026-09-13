-- فحص للقراءة فقط: شغّله مرتين بفاصل دقيقة واحتفظ بالنتيجتين.
-- يعرض عدادات تهيئة طلبات API دون نصوص الطلبات أو بيانات المستخدمين.
-- لا يعيد ضبط الإحصاءات ولا يغيّر إعدادات قاعدة البيانات.
begin read only;
set local search_path = pg_catalog, extensions, public;

select
  statement_timestamp() as sampled_at,
  i.stats_reset,
  s.dbid,
  s.userid,
  r.rolname as execution_role,
  s.queryid,
  s.toplevel,
  s.calls,
  round(s.total_exec_time::numeric, 3) as total_exec_ms,
  round(s.mean_exec_time::numeric, 6) as mean_exec_ms,
  s.rows
from pg_stat_statements s
cross join pg_stat_statements_info i
left join pg_roles r on r.oid = s.userid
where s.dbid = (select oid from pg_database where datname = current_database())
  and s.query ilike '%set_config%'
  and s.query ilike '%request.jwt.claims%'
  and s.query not ilike '%pg_stat_statements%'
order by s.calls desc;

commit;
