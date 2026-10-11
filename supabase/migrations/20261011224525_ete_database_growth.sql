begin;

create table if not exists public.ete_usage_history (
 workspace_id uuid not null references public.ete_workspaces(id) on delete cascade,
 day date not null,
 measured_at timestamptz not null default now(),
 state_bytes bigint not null,
 table_bytes bigint not null,
 database_bytes bigint not null,
 record_count bigint not null,
 counts jsonb not null,
 primary key (workspace_id,day)
);
alter table public.ete_usage_history enable row level security;
revoke all on public.ete_usage_history from public,anon,authenticated;
grant select on public.ete_usage_history to authenticated;
grant all on public.ete_usage_history to service_role;
create policy ete_usage_admin_read on public.ete_usage_history for select to authenticated
 using(ete_private.member_role(workspace_id)='admin');

create or replace function ete_private.record_usage(p_workspace uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_state jsonb; v_state_bytes bigint; v_tables bigint; v_database bigint; v_counts jsonb;
 v_months bigint; v_readings bigint; v_orders bigint; v_services bigint; v_products bigint;
 v_items bigint; v_reports bigint; v_results bigint; v_mtrs bigint; v_users bigint;
begin
 select state,pg_catalog.pg_column_size(state) into v_state,v_state_bytes
 from public.ete_workspaces where id=p_workspace;
 if not found then return; end if;
 select count(*) into v_months from pg_catalog.jsonb_each(v_state->'months');
 select count(*) into v_readings from pg_catalog.jsonb_each(v_state->'months') m
 cross join lateral pg_catalog.jsonb_each(m.value->'records') r
 where exists (select 1 from pg_catalog.jsonb_each_text(r.value) f
  where f.key in ('balde','calhaEntrada','ph','temperatura','cloro','solidosSedimentaveis','calhaSaida') and coalesce(f.value,'')<>'');
 select count(*) into v_orders from pg_catalog.jsonb_each(v_state->'orders');
 select count(*) into v_services from pg_catalog.jsonb_each(v_state->'serviceNotes');
 select count(*) into v_products from pg_catalog.jsonb_each(v_state->'productEntries');
 select count(*) into v_items from pg_catalog.jsonb_each(v_state->'productEntries') d
 cross join lateral pg_catalog.jsonb_array_elements(d.value->'items');
 select count(*) into v_reports from pg_catalog.jsonb_each(v_state->'reports');
 select count(*) into v_results from pg_catalog.jsonb_each(v_state->'reports') d
 cross join lateral pg_catalog.jsonb_array_elements(d.value->'results');
 select count(*) into v_mtrs from pg_catalog.jsonb_each(v_state->'mtrs');
 select count(*) into v_users from public.ete_members where workspace_id=p_workspace;
 v_counts=pg_catalog.jsonb_build_object('months',v_months,'readings',v_readings,'orders',v_orders,
  'serviceOrders',v_services,'productEntries',v_products,'productItems',v_items,'reports',v_reports,
  'results',v_results,'mtrs',v_mtrs,'users',v_users);
 select coalesce(sum(pg_catalog.pg_total_relation_size(c.oid)),0) into v_tables
 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r'
 and c.relname in ('ete_workspaces','ete_members','ete_audit','ete_usage_history');
 v_database=pg_catalog.pg_database_size(pg_catalog.current_database());
 insert into public.ete_usage_history(workspace_id,day,measured_at,state_bytes,table_bytes,database_bytes,record_count,counts)
 values(p_workspace,(now() at time zone 'UTC')::date,now(),v_state_bytes,v_tables,v_database,
  v_months+v_readings+v_orders+v_services+v_products+v_reports+v_mtrs,v_counts)
 on conflict(workspace_id,day) do update set measured_at=excluded.measured_at,
  state_bytes=excluded.state_bytes,table_bytes=excluded.table_bytes,database_bytes=excluded.database_bytes,
  record_count=excluded.record_count,counts=excluded.counts;
end $$;
revoke all on function ete_private.record_usage(uuid) from public,anon,authenticated;

create or replace function ete_private.track_usage() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 perform ete_private.record_usage(new.id);
 return new;
end $$;
revoke all on function ete_private.track_usage() from public,anon,authenticated;
create trigger ete_track_usage after insert or update of state on public.ete_workspaces
 for each row execute function ete_private.track_usage();

create or replace function ete_private.database_usage(p_workspace uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_current jsonb; v_history jsonb;
begin
 if auth.uid() is null or ete_private.member_role(p_workspace) is distinct from 'admin' then
  raise exception 'ETE_FORBIDDEN: somente o administrador pode acompanhar o banco';
 end if;
 perform ete_private.record_usage(p_workspace);
 select pg_catalog.to_jsonb(h)-'workspace_id' into v_current
 from public.ete_usage_history h where workspace_id=p_workspace
 order by day desc limit 1;
 select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(h)-'workspace_id' order by h.day),'[]'::jsonb)
 into v_history from (select * from public.ete_usage_history where workspace_id=p_workspace
  order by day desc limit 366) h;
 return pg_catalog.jsonb_build_object('current',v_current,'history',v_history,'timezone','UTC');
end $$;
revoke all on function ete_private.database_usage(uuid) from public,anon;
grant execute on function ete_private.database_usage(uuid) to authenticated;
create or replace function public.ete_database_usage(p_workspace uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select ete_private.database_usage(p_workspace) $$;
revoke all on function public.ete_database_usage(uuid) from public,anon;
grant execute on function public.ete_database_usage(uuid) to authenticated;

-- Seed only today's measured values; no historical values are estimated.
do $$ declare v_id uuid; begin
 for v_id in select id from public.ete_workspaces loop perform ete_private.record_usage(v_id); end loop;
end $$;
commit;
