-- 1. Crie o primeiro usuário em Supabase > Authentication > Users > Add user.
-- 2. Substitua somente o email abaixo pelo email desse usuário e execute.
-- Não escreva a senha no SQL nem em arquivos do GitHub.
begin;
do $$
declare account_id uuid; workspace uuid;
begin
 select id into account_id from auth.users where lower(email)=lower('SEU_EMAIL_AQUI');
 if account_id is null then raise exception 'Crie primeiro o usuário no painel Authentication e informe seu email neste script.'; end if;
 select id into workspace from public.ete_workspaces where slug='amesc-ete';
 if workspace is null then raise exception 'Execute primeiro o SQL do banco AMESC ETE.'; end if;
 insert into public.ete_members(workspace_id,user_id,display_name,role,active)
 values(workspace,account_id,'Administrador','admin',true)
 on conflict(workspace_id,user_id) do update set role='admin',active=true;
end $$;
commit;
