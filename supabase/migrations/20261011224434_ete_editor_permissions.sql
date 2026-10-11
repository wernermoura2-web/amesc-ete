begin;
create or replace function ete_private.check_editor_changes(p_old jsonb,p_next jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare v_collection text; v_month_key text; v_month jsonb; v_previous jsonb; v_id text; v_order jsonb;
begin
 foreach v_collection in array array['reports','serviceNotes','productEntries','mtrs'] loop
  if coalesce(p_old->v_collection,'{}'::jsonb) is distinct from coalesce(p_next->v_collection,'{}'::jsonb) then
   raise exception 'ETE_FORBIDDEN: somente o administrador pode inserir ou alterar documentos';
  end if;
 end loop;
 for v_month_key,v_month in select key,value from jsonb_each(p_old->'months') loop
  v_previous=p_next->'months'->v_month_key;
  if v_previous is null then raise exception 'ETE_FORBIDDEN: somente o administrador pode remover monitoramentos'; end if;
  if v_month->>'status' is distinct from v_previous->>'status' or coalesce(v_month->>'finalizedAt','') is distinct from coalesce(v_previous->>'finalizedAt','') then
   raise exception 'ETE_FORBIDDEN: somente o administrador pode finalizar ou reabrir meses';
  end if;
 end loop;
 for v_month_key,v_month in select key,value from jsonb_each(p_next->'months') loop
  if not (p_old->'months' ? v_month_key) and (v_month->>'status'<>'open' or coalesce(v_month->>'finalizedAt','')<>'') then
   raise exception 'ETE_FORBIDDEN: o editor pode criar somente monitoramentos abertos';
  end if;
 end loop;
 for v_id in select key from jsonb_each(p_old->'orders') union select key from jsonb_each(p_next->'orders') loop
  v_previous=p_old->'orders'->v_id;v_order=p_next->'orders'->v_id;
  if v_previous is not distinct from v_order then continue; end if;
  if v_previous is null then
   if coalesce(v_order->>'evaluation','pending')<>'pending' or coalesce(v_order->>'approvalDate','')<>'' then
    raise exception 'ETE_FORBIDDEN: somente o administrador pode avaliar ou aprovar ordens de serviço';
   end if;
  else
   if coalesce(v_previous->>'evaluation','pending')<>'pending' or coalesce(v_previous->>'approvalDate','')<>'' then
    raise exception 'ETE_FORBIDDEN: somente o administrador pode alterar uma OS avaliada';
   end if;
   if v_order is not null and jsonb_build_array(v_previous->'evaluation',v_previous->'engineer',v_previous->'approvalDate') is distinct from jsonb_build_array(v_order->'evaluation',v_order->'engineer',v_order->'approvalDate') then
    raise exception 'ETE_FORBIDDEN: somente o administrador pode avaliar ou aprovar ordens de serviço';
   end if;
  end if;
 end loop;
end $$;
revoke all on function ete_private.check_editor_changes(jsonb,jsonb) from public,anon,authenticated;


create or replace function ete_private.save_state(p_workspace uuid,p_expected_revision bigint,p_state jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare old jsonb; rev bigint; k text; v jsonb; next_month jsonb; collection text; d text; r jsonb; previous jsonb; date_field text; dates text[]; dt text;
begin
 if auth.uid() is null or coalesce(ete_private.member_role(p_workspace),'') not in ('admin','editor') then raise exception 'ETE_FORBIDDEN: você não pode alterar os registros'; end if;
 select state,revision into old,rev from public.ete_workspaces where id=p_workspace for update;
 if not found then raise exception 'ETE_FORBIDDEN: espaço de trabalho não encontrado'; end if;
 if p_expected_revision is null or p_expected_revision<0 or rev<>p_expected_revision then raise exception 'ETE_CONFLICT: outra pessoa alterou os registros; recarregue os dados salvos'; end if;
 perform ete_private.validate_state(p_state);
 if ete_private.member_role(p_workspace)='editor' then perform ete_private.check_editor_changes(old,p_state); end if;
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

create or replace function public.ete_import_state(p_workspace uuid,p_expected_revision bigint,p_state jsonb) returns bigint
language plpgsql security invoker set search_path = '' as $$
begin
 if ete_private.member_role(p_workspace) is distinct from 'admin' then
  raise exception 'ETE_FORBIDDEN: somente o administrador pode importar registros';
 end if;
 return ete_private.save_state(p_workspace,p_expected_revision,p_state);
end $$;
revoke all on function public.ete_import_state(uuid,bigint,jsonb) from public,anon;
grant execute on function public.ete_import_state(uuid,bigint,jsonb) to authenticated;
commit;
