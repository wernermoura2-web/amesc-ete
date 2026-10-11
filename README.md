# AMESC · Monitoramento diário da ETE

Sistema em português com medições diárias, OS, laudos, produtos, MTR, importação com conferência e impressão mensal. O HTML funciona sozinho; quando o Supabase está configurado, exige email e senha e salva os registros no banco compartilhado.

## Situação desta entrega

O HTML já inclui o projeto `https://kwvszryduljbfwbytgma.supabase.co` e a chave pública fornecida. A conexão respondeu corretamente ao teste de autenticação. A função `ete_list_workspaces` ainda não foi encontrada no banco em 11/10/2026: falta executar o SQL, criar o primeiro administrador e publicar a função de usuários. O repositório GitHub também aguarda a conexão da conta. Esta versão abre a tela de login e não passa a salvar no banco antes da instalação e liberação do usuário.

## Instalação no Supabase

1. Abra o projeto `kwvszryduljbfwbytgma` no Supabase. Em SQL Editor, execute `supabase/migrations/202610110001_ete.sql`.
2. Em Authentication → Users, crie o primeiro usuário com email e senha. Desative o cadastro público em Authentication → Providers → Email → Allow new users to sign up.
3. Copie `supabase/02_primeiro_administrador.sql`, substitua `SEU_EMAIL_AQUI` pelo email criado e execute. Não coloque senha no SQL.
4. Publique a função `supabase/functions/ete-admin-users/index.ts`, com a configuração de `supabase/config.toml`. Ela verifica a sessão com `auth.getUser()` e confere a permissão de administrador antes de criar uma conta. As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas no ambiente da função, nunca no HTML.
5. O endereço e a chave **publishable** já estão incluídos neste HTML. Se o projeto mudar, atualize com `configurar_html.py --url https://SEU-PROJETO.supabase.co --publishable-key SUA_CHAVE_PUBLICA`. A configuração incluída no arquivo vale para todos os usuários do HTML publicado.
6. Entre com o primeiro administrador. Em **Minha conta → Usuários**, cadastre os demais usuários. O cadastro é direto; o sistema não envia emails de convite. A senha inicial tem no mínimo 8 caracteres e precisa atender às regras de senha do projeto.

## Hospedagem no GitHub

Crie ou use o repositório `amesc-ete`, com estes arquivos na raiz. Em Settings → Pages, escolha **GitHub Actions**. O fluxo `.github/workflows/pages.yml` publica apenas `index.html`; arquivos SQL e função não são enviados ao site. Depois do envio ao branch `main`, confirme o resultado do workflow e use a URL retornada pelo GitHub Pages. A disponibilidade de Pages em um repositório privado depende do plano da conta.

O HTML distribuído neste pacote inicia sem laudos de exemplo nem dados dos documentos enviados. O endereço do Supabase e a chave publishable podem ficar no repositório. Senhas de usuários, chave secreta e arquivos de documentos não devem ficar nele.

## Usar os registros anteriores

Antes de conectar, no HTML atual clique em **Guardar cópia** e exporte **todos os anos em JSON**. Após entrar no sistema conectado, clique em **Abrir cópia**, escolha esse JSON, confira a prévia e importe. O banco local fica preservado; não há migração silenciosa. O sistema impede que uma revisão antiga sobrescreva o que outra pessoa acabou de salvar; nesse caso, guarde uma cópia e recarregue os dados.

## Acessos e dados

- **Registrar:** medições, documentos, importação, finalizar/reabrir meses, impressão e exportação.
- **Consultar:** leitura, impressão e exportação. O banco recusa alterações mesmo que alguém manipule os botões do HTML.
- **Administrador:** tudo acima e cadastro/ativação/desativação de usuários.

O banco guarda o estado estruturado em JSONB, preservando os formatos e registros históricos do HTML. As vistas `ete_daily_readings`, `ete_documents`, `ete_analysis_results` e `ete_product_items` permitem consultas SQL por dia, documento, análise e produto. RLS limita os dados ao espaço de trabalho do usuário. RPCs verificam a permissão, o fechamento mensal e a revisão dentro da transação. `ete_audit` registra usuário, ação, data e revisão, sem guardar documentos ou senhas.

Os resultados dos laudos aparecem no **dia da coleta**. OS internas aparecem pelo número na coluna depois do dia; OS lidas, MTR e produtos aparecem abaixo da data correspondente. A entrada de produtos usa a data de entrega. CCL padrão: `IN105949`. Responsáveis padrão: Rildo Ramos da Silva e Werner Moura Ewald.

## Leitura de fotos

PDF com texto, PDF digitalizado, JPG, PNG, WEBP e XML de NF-e são aceitos. A leitura de imagens usa Tesseract no aparelho, com modelos de português e inglês. Fotos sem dados suficientes recebem uma segunda tentativa com contraste ajustado. A inicialização do motor foi corrigida para encerrar o processo e informar falhas no carregamento do modelo. Falhas e demora excessiva são informadas; a tela deixa os campos disponíveis para preenchimento e correção. **Ver texto lido** ajuda a conferir o reconhecimento e desaparece ao fechar a leitura; esse texto não é salvo.

No teste real com a OS amarela, a segunda leitura reconheceu `2181`; a data manuscrita continuou em branco. A planilha manuscrita reconheceu títulos impressos, mas muitos números não ficaram confiáveis. Sempre confira antes de importar. O sistema não inventa resultados, e não promete leitura perfeita de manuscritos. Fotos e PDFs não são enviados ao Supabase nem armazenados; somente campos confirmados são salvos.

## Validação feita

Migração executada em PostgreSQL via PGlite, com testes de RLS, usuários, conflito, validação, fechamento/reabertura, datas dos laudos e fórmulas. Interface existente verificada com um harness DOM; PDFs enviados lidos com o motor PDF incorporado e foto da OS testada com o motor OCR incorporado. Login, adaptador de banco e função de usuários têm testes com respostas controladas. Não houve teste de renderização em navegador, login em um projeto Supabase real ou publicação no GitHub nesta etapa; esses últimos dependem das conexões da conta.
