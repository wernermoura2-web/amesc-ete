-- Índices de vínculos e funções privilegiadas no esquema privado.
begin;

create index if not exists ete_members_user_id_idx on public.ete_members(user_id,workspace_id);

create index if not exists ete_audit_workspace_id_idx on public.ete_audit(workspace_id,created_at desc);

create index if not exists ete_audit_actor_id_idx on public.ete_audit(actor_id);

create or replace function ete_private.save_state(p_workspace uuid,p_expected_revision bigint,p_state jsonb) returns bigint
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

revoke all on function ete_private.save_state(uuid,bigint,jsonb) from public,anon,authenticated;

grant execute on function ete_private.save_state(uuid,bigint,jsonb) to authenticated;

create or replace function public.ete_save_state(p_workspace uuid,p_expected_revision bigint,p_state jsonb) returns bigint
language sql security invoker set search_path = '' as $$
 select ete_private.save_state(p_workspace,p_expected_revision,p_state)
$$;

revoke all on function public.ete_save_state(uuid,bigint,jsonb) from public,anon;

grant execute on function public.ete_save_state(uuid,bigint,jsonb) to authenticated;

create or replace function ete_private.list_members(p_workspace uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
 if ete_private.member_role(p_workspace) is distinct from 'admin' then raise exception 'ETE_FORBIDDEN: somente o administrador pode ver os usuários'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',m.display_name,'email',u.email,'role',m.role,'active',m.active) order by u.email),'[]') into result
 from public.ete_members m join auth.users u on u.id=m.user_id where m.workspace_id=p_workspace;
 return result;
end $$;

revoke all on function ete_private.list_members(uuid) from public,anon,authenticated;

grant execute on function ete_private.list_members(uuid) to authenticated;

create or replace function public.ete_list_members(p_workspace uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
 select ete_private.list_members(p_workspace)
$$;

revoke all on function public.ete_list_members(uuid) from public,anon;

grant execute on function public.ete_list_members(uuid) to authenticated;

create or replace function ete_private.set_member(p_workspace uuid,p_user uuid,p_role text,p_active boolean,p_name text) returns void
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

revoke all on function ete_private.set_member(uuid,uuid,text,boolean,text) from public,anon,authenticated;

grant execute on function ete_private.set_member(uuid,uuid,text,boolean,text) to authenticated;

create or replace function public.ete_set_member(p_workspace uuid,p_user uuid,p_role text,p_active boolean,p_name text) returns void
language sql security invoker set search_path = '' as $$
 select ete_private.set_member(p_workspace,p_user,p_role,p_active,p_name)
$$;

revoke all on function public.ete_set_member(uuid,uuid,text,boolean,text) from public,anon;

grant execute on function public.ete_set_member(uuid,uuid,text,boolean,text) to authenticated;

commit;
