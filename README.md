# AMESC · Monitoramento diário da ETE

Sistema em português com medições diárias, OS, laudos, produtos, MTR, importação com conferência e impressão mensal. O HTML funciona sozinho; quando o Supabase está configurado, exige email e senha e salva os registros no banco compartilhado.

## Situação desta entrega

O banco está instalado no projeto **amesc-ete**, `https://kwvszryduljbfwbytgma.supabase.co`. Foram aplicadas e verificadas as migrações `20261011215931_amesc_ete_initial` e `20261011220633_ete_permissions_indexes`. A função `ete-admin-users` está ativa, com validação de JWT na plataforma e consulta do usuário no servidor. O HTML já inclui o endereço e a chave pública. **Falta criar o primeiro usuário em Authentication e liberá-lo como administrador.** O repositório GitHub aguarda a conexão da conta.

## Instalação no Supabase

1. Neste projeto, o SQL já está aplicado: não é necessário executá-lo de novo. Para instalar em outro projeto, execute os dois arquivos de `supabase/migrations` na ordem do nome, ou use o arquivo combinado `Banco_AMESC_ETE.sql`.
2. Em Authentication → Users, crie o primeiro usuário com email e senha. Desative o cadastro público em Authentication → Providers → Email → Allow new users to sign up.
3. Copie `supabase/02_primeiro_administrador.sql`, substitua `SEU_EMAIL_AQUI` pelo email criado e execute. Não coloque senha no SQL.
4. A função `supabase/functions/ete-admin-users/index.ts` já foi publicada neste projeto. Para uma nova instalação, publique com a configuração de `supabase/config.toml`, mantendo `verify_jwt = true`. Ela verifica a sessão com `auth.getUser(token)` e confere a permissão de administrador antes de criar uma conta. As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas no ambiente da função, nunca no HTML.
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

O banco guarda o estado estruturado em JSONB, preservando os formatos e registros históricos do HTML. As vistas `ete_daily_readings`, `ete_documents`, `ete_analysis_results` e `ete_product_items` permitem consultas SQL por dia, documento, análise e produto. RLS limita os dados ao espaço de trabalho do usuário. As funções privilegiadas ficam no esquema privado; os RPCs públicos executam como o usuário e chamam essas funções, que verificam a permissão, o fechamento mensal e a revisão dentro da transação. `ete_audit` registra usuário, ação, data e revisão, sem guardar documentos ou senhas.

Os resultados dos laudos aparecem no **dia da coleta**. OS internas aparecem pelo número na coluna depois do dia; OS lidas, MTR e produtos aparecem abaixo da data correspondente. A entrada de produtos usa a data de entrega. CCL padrão: `IN105949`. Responsáveis padrão: Rildo Ramos da Silva e Werner Moura Ewald.

## Leitura de fotos

PDF com texto, PDF digitalizado, JPG, PNG, WEBP e XML de NF-e são aceitos. A leitura de imagens usa Tesseract no aparelho, com modelos de português e inglês. Fotos sem dados suficientes recebem uma segunda tentativa com contraste ajustado. A inicialização do motor foi corrigida para encerrar o processo e informar falhas no carregamento do modelo. Falhas e demora excessiva são informadas; a tela deixa os campos disponíveis para preenchimento e correção. **Ver texto lido** ajuda a conferir o reconhecimento e desaparece ao fechar a leitura; esse texto não é salvo.

No teste real com a OS amarela, a segunda leitura reconheceu `2181`; a data manuscrita continuou em branco. A planilha manuscrita reconheceu títulos impressos, mas muitos números não ficaram confiáveis. Sempre confira antes de importar. O sistema não inventa resultados, e não promete leitura perfeita de manuscritos. Fotos e PDFs não são enviados ao Supabase nem armazenados; somente campos confirmados são salvos.

## Validação feita

As duas migrações foram executadas no Supabase real, PostgreSQL 17.11. Testes no banco confirmaram o bloqueio de leitura, gravação, lista de usuários e autoatribuição de administrador por um usuário sem liberação. A API real bloqueou o acesso anônimo aos dados e à função de cadastro. As fórmulas de vazão foram conferidas no servidor. O verificador de segurança retornou zero alertas; o de desempenho apenas informou que os índices novos ainda não têm uso, esperado num banco vazio ([referência do Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)).

As duas migrações também passaram em 27 testes PostgreSQL via PGlite: RLS, perfis, conflito, validação, fechamento/reabertura, datas dos laudos e fórmulas. A função de cadastro passou nos testes de JWT explícito, administração e reversão de cadastro incompleto. Login e adaptador têm testes com respostas controladas. A interface existente foi verificada com um harness DOM; os PDFs enviados foram lidos pelo motor incorporado e a foto da OS foi testada pelo OCR incorporado. Não houve login com uma conta real, criação real de usuário pela função, teste de renderização em navegador ou publicação no GitHub nesta etapa. O primeiro login depende do cadastro e da liberação do administrador.
