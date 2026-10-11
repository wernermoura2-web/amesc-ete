-- AMESC ETE: dados confirmados; documentos e fotografias não são armazenados.
begin;
create schema if not exists ete_private;
revoke all on schema ete_private from public, anon;
grant usage on schema ete_private to authenticated;

create table if not exists public.ete_workspaces (
 id uuid primary key default gen_random_uuid(),
 slug text not null unique,
 name text not null,
 state jsonb not null default '{"schema":"ete-monitoramento-v1","version":1,"profile":{"organization":"CEMERU","unit":"AMESC — R. Felipe Cardoso","responsible":"Rildo Ramos da Silva","engineer":"Werner Moura Ewald"},"months":{},"reports":{},"orders":{},"orderCounters":{},"serviceNotes":{},"productEntries":{},"mtrs":{},"revision":0}',
 revision bigint not null default 0 check (revision >= 0),
 updated_at timestamptz not null default now(),
 check (jsonb_typeof(state) = 'object')
);
create table if not exists public.ete_members (
 workspace_id uuid not null references public.ete_workspaces on delete cascade,
 user_id uuid not null references auth.users on delete cascade,
 display_name text not null default '',
 role text not null check (role in ('admin','editor','viewer')),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 primary key(workspace_id,user_id)
);
create table if not exists public.ete_audit (
 id bigint generated always as identity primary key,
 workspace_id uuid not null references public.ete_workspaces on delete cascade,
 actor_id uuid references auth.users on delete set null,
 action text not null,
 revision bigint,
 created_at timestamptz not null default now()
);
-- Não há políticas INSERT/UPDATE/DELETE para clientes: alterações passam pelos RPCs.
alter table public.ete_workspaces enable row level security;
alter table public.ete_members enable row level security;
alter table public.ete_audit enable row level security;
revoke all on public.ete_workspaces,public.ete_members,public.ete_audit from anon,authenticated;
grant select on public.ete_workspaces,public.ete_members,public.ete_audit to authenticated;
grant all on public.ete_workspaces,public.ete_members,public.ete_audit to service_role;
grant usage,select on sequence public.ete_audit_id_seq to service_role;

create or replace function ete_private.member_role(p_workspace uuid) returns text
language sql stable security definer set search_path = '' as $$
 select m.role from public.ete_members m
 where m.workspace_id=p_workspace and m.user_id=auth.uid() and m.active
$$;
revoke all on function ete_private.member_role(uuid) from public,anon;
grant execute on function ete_private.member_role(uuid) to authenticated;
drop policy if exists ete_workspace_read on public.ete_workspaces;
create policy ete_workspace_read on public.ete_workspaces for select to authenticated
 using(ete_private.member_role(id) is not null);
drop policy if exists ete_member_read on public.ete_members;
create policy ete_member_read on public.ete_members for select to authenticated
 using(ete_private.member_role(workspace_id) is not null);
drop policy if exists ete_audit_read on public.ete_audit;
create policy ete_audit_read on public.ete_audit for select to authenticated
 using(ete_private.member_role(workspace_id)='admin');

create or replace function ete_private.valid_date(v text) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
 return v ~ '^\d{4}-\d{2}-\d{2}$' and to_char(v::date,'YYYY-MM-DD')=v
  and extract(year from v::date) between 1900 and 2200;
exception when others then return false;
end $$;
create or replace function ete_private.number_or_null(v text) returns numeric
language plpgsql immutable set search_path = '' as $$
begin
 if trim(coalesce(v,'')) !~ '^-?(\d+([.,]\d+)?|[.,]\d+)$' then return null; end if;
 return replace(trim(v),',','.')::numeric;
exception when others then return null;
end $$;
revoke all on function ete_private.valid_date(text),ete_private.number_or_null(text) from public,anon;
grant execute on function ete_private.valid_date(text),ete_private.number_or_null(text) to authenticated;

create or replace function ete_private.validate_state(s jsonb) returns void
language plpgsql set search_path = '' as $$
declare k text; v jsonb; d text; r jsonb; field text; n numeric;
 year_no int; month_no int; last_day int; filled boolean; item jsonb; date_field text;
begin
 if jsonb_typeof(s) <> 'object' or s->>'schema' is distinct from 'ete-monitoramento-v1'
  or s->>'version' is distinct from '1' or octet_length(s::text)>20971520 then
  raise exception 'ETE_INVALID: arquivo de dados inválido ou maior que 20 MB';
 end if;
 if exists(select 1 from jsonb_object_keys(s) as x(key) where key not in ('schema','version','profile','months','reports','orders','orderCounters','serviceNotes','productEntries','mtrs','revision','updatedAt','lastOpened')) then raise exception 'ETE_INVALID: campo desconhecido no arquivo'; end if;
 if jsonb_path_exists(s,'$.** ? (@.type() == "object").keyvalue() ? (@.key == "file" || @.key == "pdf" || @.key == "image" || @.key == "rawText" || @.key == "ocrText")') then
  raise exception 'ETE_INVALID: somente os dados confirmados podem ser salvos';
 end if;
 foreach k in array array['profile','months','reports','orders','orderCounters','serviceNotes','productEntries','mtrs'] loop
  if jsonb_typeof(s->k) is distinct from 'object' then raise exception 'ETE_INVALID: coleção inválida: %',k; end if;
 end loop;
 for k,v in select key,value from jsonb_each(s->'months') loop
  if k !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'ETE_INVALID: mês inválido'; end if;
  year_no=left(k,4)::int; month_no=right(k,2)::int;
  if year_no not between 1900 and 2200 or (v->>'year')::int is distinct from year_no or (v->>'month')::int is distinct from month_no
   or coalesce(v->>'status','') not in ('open','finalized') or jsonb_typeof(v->'records') is distinct from 'object' then
   raise exception 'ETE_INVALID: dados do mês inválidos';
  end if;
  last_day=extract(day from (make_date(year_no,month_no,1)+interval '1 month - 1 day'));
  for d,r in select key,value from jsonb_each(v->'records') loop
   if d !~ '^\d{1,2}$' or d::int not between 1 and last_day or jsonb_typeof(r)<>'object' then raise exception 'ETE_INVALID: dia inválido'; end if;
   filled=false;
   foreach field in array array['balde','calhaEntrada','ph','temperatura','cloro','solidosSedimentaveis','calhaSaida'] loop
    if length(coalesce(r->>field,''))>32 then raise exception 'ETE_INVALID: leitura muito extensa'; end if;
    if trim(coalesce(r->>field,''))<>'' then filled=true; end if;
   end loop;
   -- Rascunhos podem conter uma digitação incompleta; finalizar exige valores válidos.
   if v->>'status'='finalized' and filled then
    foreach field in array array['balde','ph','temperatura','calhaSaida'] loop
     if trim(coalesce(r->>field,''))='' then raise exception 'ETE_INVALID: falta % no dia %',field,d; end if;
    end loop;
    foreach field in array array['balde','calhaEntrada','ph','temperatura','cloro','solidosSedimentaveis','calhaSaida'] loop
     if trim(coalesce(r->>field,''))<>'' then
      n=ete_private.number_or_null(r->>field);
      if n is null or abs(n)>1000000000 or (field='ph' and n not between 0 and 14)
       or (field<>'temperatura' and n<0) then raise exception 'ETE_INVALID: confira % no dia %',field,d; end if;
     end if;
    end loop;
   end if;
  end loop;
 end loop;
 foreach k in array array['reports','orders','serviceNotes','productEntries','mtrs'] loop
  if (select count(*) from jsonb_each(s->k))>10000 then raise exception 'ETE_INVALID: registros demais'; end if;
  date_field=case k when 'reports' then 'collectionDate' when 'mtrs' then 'serviceDate' else 'date' end;
  for d,r in select key,value from jsonb_each(s->k) loop
   if d !~ '^[-a-zA-Z0-9_:.]{1,100}$' or d in ('__proto__','constructor','prototype')
    or r->>'id' is distinct from d or jsonb_typeof(r)<>'object'
    or not coalesce(ete_private.valid_date(r->>date_field),false) then raise exception 'ETE_INVALID: registro ou data inválida em %',k; end if;
   if not (s->'months' ? left(r->>date_field,7)) and (k<>'orders' or coalesce((r->>'linked')::boolean,false)) then raise exception 'ETE_INVALID: o mês do documento não existe'; end if;
   if k<>'productEntries' and trim(coalesce(r->>'number',''))='' and k<>'reports' then raise exception 'ETE_INVALID: informe o número do documento'; end if;
   if k='reports' then
    if trim(coalesce(r->>'laboratory',''))='' or jsonb_typeof(r->'results') is distinct from 'array'
     or jsonb_array_length(r->'results')>100 then raise exception 'ETE_INVALID: laboratório ou resultados inválidos'; end if;
    if coalesce(r->>'resultDate','')<>'' and (not ete_private.valid_date(r->>'resultDate') or r->>'resultDate'<r->>'collectionDate') then raise exception 'ETE_INVALID: data de resultado inválida'; end if;
    if coalesce(r->>'laboratoryCNPJ','')<>'' and regexp_replace(r->>'laboratoryCNPJ','\D','','g') !~ '^\d{14}$' then raise exception 'ETE_INVALID: CNPJ inválido'; end if;
   elsif k='orders' then
    if coalesce(r->>'year','') !~ '^\d{4}$' or coalesce(r->>'sequence','') !~ '^\d{1,6}$' then raise exception 'ETE_INVALID: numeração de OS inválida'; end if;
    if (r->>'sequence')::int not between 1 and 999999 or (r->>'year')::int not between 1900 and 2200
     or r->>'number' is distinct from lpad(r->>'sequence',6,'0')||'/'||(r->>'year')
     or coalesce((s->'orderCounters'->>(r->>'year'))::int,0)<(r->>'sequence')::int then raise exception 'ETE_INVALID: contador ou número de OS inválido'; end if;
    if jsonb_typeof(r->'tasks') is distinct from 'array' or jsonb_typeof(r->'operationTypes') is distinct from 'array'
     or jsonb_array_length(r->'operationTypes')=0 then raise exception 'ETE_INVALID: seleções de OS inválidas'; end if;
   elsif k='productEntries' then
    if jsonb_typeof(r->'items') is distinct from 'array' or jsonb_array_length(r->'items') not between 1 and 100 then raise exception 'ETE_INVALID: produtos inválidos'; end if;
    for item in select value from jsonb_array_elements(r->'items') loop
     n=ete_private.number_or_null(item->>'quantity');
     if trim(coalesce(item->>'product',''))='' or n is null or n<=0 or n>1000000000 then raise exception 'ETE_INVALID: produto ou quantidade inválida'; end if;
    end loop;
   end if;
  end loop;
 end loop;
 for k,v in select key,value from jsonb_each(s->'orderCounters') loop
  if k !~ '^\d{4}$' or v::text !~ '^\d{1,9}$' then raise exception 'ETE_INVALID: contador de OS inválido'; end if;
 end loop;
 -- A numeração de OS gerada internamente é única dentro do espaço de trabalho.
 if exists(select 1 from jsonb_each(s->'orders') group by value->>'number' having count(*)>1) then raise exception 'ETE_INVALID: número de OS duplicado'; end if;
end $$;
revoke all on function ete_private.validate_state(jsonb) from public,anon,authenticated;

create or replace function public.ete_list_workspaces() returns jsonb
language sql stable security invoker set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'role',m.role) order by w.name),'[]')
 from public.ete_workspaces w join public.ete_members m on m.workspace_id=w.id
 where m.user_id=auth.uid() and m.active
$$;
create or replace function public.ete_read_state(p_workspace uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare result jsonb;
begin
 select state||jsonb_build_object('revision',revision,'updatedAt',updated_at) into result from public.ete_workspaces where id=p_workspace;
 if result is null then raise exception 'ETE_FORBIDDEN: acesso não permitido'; end if;
 return result;
end $$;
create or replace function ete_private.order_projection(o jsonb) returns jsonb
language sql immutable set search_path = '' as $$
 select jsonb_build_array(o->'date',o->'linked',o->'number',o->'tasks',o->'otherTask',o->'performedServices',o->'manifestNumber')
$$;
revoke all on function ete_private.order_projection(jsonb) from public,anon,authenticated;
create or replace function public.ete_save_state(p_workspace uuid,p_expected_revision bigint,p_state jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare old jsonb; rev bigint; k text; v jsonb; next_month jsonb; collection text; d text; r jsonb; previous jsonb; date_field text; dates text[]; dt text;
begin
 if auth.uid() is null or coalesce(ete_private.member_role(p_workspace),'') not in ('admin','editor') then raise exception 'ETE_FORBIDDEN: você não pode alterar os registros'; end if;
 select state,revision into old,rev from public.ete_workspaces where id=p_workspace for update;
 if not found then raise exception 'ETE_FORBIDDEN: espaço de trabalho não encontrado'; end if;
 if p_expected_revision is null or p_expected_revision<0 or rev<>p_expected_revision then raise exception 'ETE_CONFLICT: outra pessoa alterou os registros; recarregue os dados salvos'; end if;
 perform ete_private.validate_state(p_state);
 for k,v in select key,value from jsonb_each(old->'months') where value->>'status'='finalized' loop
  next_month=p_state->'months'->k;
  if next_month is null then raise exception 'ETE_LOCKED: reabra o mês % antes de excluí-lo',k; end if;
  if next_month->>'status'='open' then
   if (next_month-array['status','finalizedAt','updatedAt']) is distinct from (v-array['status','finalizedAt','updatedAt']) then raise exception 'ETE_LOCKED: reabra o mês % antes de alterar os dados',k; end if;
  elsif (next_month-'updatedAt') is distinct from (v-'updatedAt') then raise exception 'ETE_LOCKED: reabra o mês % antes de alterar os dados',k;
  end if;
 end loop;
 foreach collection in array array['reports','orders','serviceNotes','productEntries','mtrs'] loop
  date_field=case collection when 'reports' then 'collectionDate' when 'mtrs' then 'serviceDate' else 'date' end;
  for d in select key from jsonb_each(coalesce(old->collection,'{}')) union select key from jsonb_each(p_state->collection) loop
   r=p_state->collection->d; previous=old->collection->d;
   if r is distinct from previous then
    if collection='orders' and ete_private.order_projection(r)=ete_private.order_projection(previous) then continue; end if;
    dates=array[previous->>date_field,r->>date_field];
    foreach dt in array dates loop
     if old->'months'->left(dt,7)->>'status'='finalized' and (collection<>'orders' or coalesce((previous->>'linked')::boolean,false) or coalesce((r->>'linked')::boolean,false)) then
      raise exception 'ETE_LOCKED: reabra o mês % antes de alterar o documento',left(dt,7);
     end if;
    end loop;
   end if;
  end loop;
 end loop;
 for k,v in select key,value from jsonb_each(coalesce(old->'orderCounters','{}')) loop
  if coalesce((p_state->'orderCounters'->>k)::bigint,0)<v::text::bigint then raise exception 'ETE_INVALID: o contador de OS não pode diminuir'; end if;
 end loop;
 rev=rev+1;
 update public.ete_workspaces set state=(p_state-array['lastOpened','updatedAt','revision'])||jsonb_build_object('revision',rev),revision=rev,updated_at=now() where id=p_workspace;
 insert into public.ete_audit(workspace_id,actor_id,action,revision) values(p_workspace,auth.uid(),'save',rev);
 return rev;
end $$;

create or replace function public.ete_list_members(p_workspace uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
 if ete_private.member_role(p_workspace) is distinct from 'admin' then raise exception 'ETE_FORBIDDEN: somente o administrador pode ver os usuários'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',m.display_name,'email',u.email,'role',m.role,'active',m.active) order by u.email),'[]') into result
 from public.ete_members m join auth.users u on u.id=m.user_id where m.workspace_id=p_workspace;
 return result;
end $$;
create or replace function public.ete_set_member(p_workspace uuid,p_user uuid,p_role text,p_active boolean,p_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if ete_private.member_role(p_workspace) is distinct from 'admin' then raise exception 'ETE_FORBIDDEN: somente o administrador pode alterar usuários'; end if;
 perform 1 from public.ete_workspaces where id=p_workspace for update;
 if p_role not in ('admin','editor','viewer') or length(p_name)>240 then raise exception 'ETE_INVALID: perfil de usuário inválido'; end if;
 if p_user=auth.uid() and (not p_active or p_role<>'admin') then raise exception 'ETE_INVALID: use outro administrador para alterar seu próprio acesso'; end if;
 if not exists(select 1 from public.ete_members where workspace_id=p_workspace and user_id=p_user) then raise exception 'ETE_INVALID: usuário não cadastrado neste sistema'; end if;
 update public.ete_members set role=p_role,active=p_active,display_name=p_name where workspace_id=p_workspace and user_id=p_user;
 insert into public.ete_audit(workspace_id,actor_id,action) values(p_workspace,auth.uid(),'member_update');
end $$;
revoke all on function public.ete_list_workspaces(),public.ete_read_state(uuid),public.ete_save_state(uuid,bigint,jsonb),public.ete_list_members(uuid),public.ete_set_member(uuid,uuid,text,boolean,text) from public,anon;
grant execute on function public.ete_list_workspaces(),public.ete_read_state(uuid),public.ete_save_state(uuid,bigint,jsonb),public.ete_list_members(uuid),public.ete_set_member(uuid,uuid,text,boolean,text) to authenticated;

-- Vistas SQL para consultas e integrações. A segurança é a do usuário conectado.
create or replace view public.ete_daily_readings with (security_invoker=true) as
 select w.id workspace_id,m.key month_key,d.key::int day_number,d.value reading,
 ete_private.number_or_null(d.value->>'balde')*5.76 inlet_m3_day,
 case when ete_private.number_or_null(d.value->>'calhaSaida')>=0 then 434.58*power(ete_private.number_or_null(d.value->>'calhaSaida')/100,1.55)*24 end outlet_m3_day
 from public.ete_workspaces w cross join lateral jsonb_each(w.state->'months') m
 cross join lateral jsonb_each(m.value->'records') d;
create or replace view public.ete_documents with (security_invoker=true) as
 select w.id workspace_id,c.key kind,d.key id,d.value data,
 case c.key when 'reports' then d.value->>'collectionDate' when 'mtrs' then d.value->>'serviceDate' else d.value->>'date' end event_date
 from public.ete_workspaces w cross join lateral jsonb_each(w.state) c
 cross join lateral jsonb_each(case when c.key in ('reports','orders','serviceNotes','productEntries','mtrs') then c.value else '{}'::jsonb end) d;
create or replace view public.ete_analysis_results with (security_invoker=true) as
 select w.id workspace_id,d.key report_id,d.value->>'number' report_number,d.value->>'collectionDate' collection_date,
 d.value->>'resultDate' result_date,d.value->>'laboratory' laboratory,d.value->>'laboratoryCNPJ' laboratory_cnpj,
 coalesce(nullif(d.value->>'ccl',''),'IN105949') ccl,d.value->>'samplePoint' sample_point,
 p.value->>'parameter' parameter,p.value->>'value' result
 from public.ete_workspaces w cross join lateral jsonb_each(w.state->'reports') d
 cross join lateral jsonb_array_elements(d.value->'results') p;
create or replace view public.ete_product_items with (security_invoker=true) as
 select w.id workspace_id,d.key entry_id,d.value->>'number' invoice_number,d.value->>'date' delivery_date,
 p.value->>'product' product,ete_private.number_or_null(p.value->>'quantity') quantity,p.value->>'unit' unit
 from public.ete_workspaces w cross join lateral jsonb_each(w.state->'productEntries') d
 cross join lateral jsonb_array_elements(d.value->'items') p;
revoke all on public.ete_daily_readings,public.ete_documents,public.ete_analysis_results,public.ete_product_items from anon;
grant select on public.ete_daily_readings,public.ete_documents,public.ete_analysis_results,public.ete_product_items to authenticated;

insert into public.ete_workspaces(slug,name) values('amesc-ete','AMESC · Monitoramento da ETE') on conflict(slug) do nothing;
commit;
