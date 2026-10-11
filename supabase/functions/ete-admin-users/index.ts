import { createClient } from 'npm:@supabase/supabase-js@2.97.0';

// Esta função roda somente no servidor. Nenhuma chave secreta vai para o HTML.
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const respond=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return respond(405,{error:'Método não permitido.'});
 const authorization=req.headers.get('Authorization')||'';
 if(!authorization.startsWith('Bearer '))return respond(401,{error:'Entre no sistema.'});
 const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:identity,error:identityError}=await caller.auth.getUser(authorization.slice(7));
 if(identityError||!identity.user)return respond(401,{error:'Entre novamente no sistema.'});
 let body;
 try{if(Number(req.headers.get('Content-Length')||0)>8192)return respond(413,{error:'Dados muito extensos.'});const text=await req.text();if(text.length>8192)return respond(413,{error:'Dados muito extensos.'});body=JSON.parse(text);}catch{return respond(400,{error:'Dados inválidos.'});}
 const {workspaceId,email,password,name='',role='editor'}=body;
 if(typeof workspaceId!=='string'||!/^[0-9a-f-]{36}$/i.test(workspaceId)||typeof email!=='string'||!/^\S+@\S+\.\S+$/.test(email)||email.length>254||typeof password!=='string'||password.length<8||password.length>128||typeof name!=='string'||name.length>240||!['admin','editor','viewer'].includes(role))return respond(400,{error:'Informe nome, email válido e senha com pelo menos 8 caracteres.'});
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:membership,error:membershipError}=await admin.from('ete_members').select('role,active').eq('workspace_id',workspaceId).eq('user_id',identity.user.id).maybeSingle();
 if(membershipError||membership?.role!=='admin'||!membership.active)return respond(403,{error:'Somente o administrador pode cadastrar usuários.'});
 const {data:created,error:creationError}=await admin.auth.admin.createUser({email:email.trim().toLowerCase(),password,email_confirm:true,user_metadata:{display_name:name}});
 if(creationError||!created.user)return respond(400,{error:creationError?.message?.includes('already')?'Este email já existe. Libere o usuário existente pelo painel Supabase.':'Não foi possível criar o usuário. Verifique o email e as regras da senha.'});
 const {error:insertError}=await admin.from('ete_members').insert({workspace_id:workspaceId,user_id:created.user.id,display_name:name,role,active:true});
 if(insertError){await admin.auth.admin.deleteUser(created.user.id);return respond(500,{error:'Não foi possível liberar o acesso. Tente novamente.'});}
 await admin.from('ete_audit').insert({workspace_id:workspaceId,actor_id:identity.user.id,action:'member_create'});
 return respond(201,{id:created.user.id,email:created.user.email,role});
});
