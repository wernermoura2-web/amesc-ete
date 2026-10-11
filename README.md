# AMESC · Monitoramento diário da ETE

Sistema em português com medições diárias, OS, laudos, produtos, MTR, importação com conferência e impressão mensal. O HTML funciona sozinho; quando o Supabase está configurado, exige email e senha e salva os registros no banco compartilhado.

## Situação desta entrega

O banco está instalado no projeto **amesc-ete**, `https://kwvszryduljbfwbytgma.supabase.co`. As quatro migrações de `supabase/migrations` estão aplicadas e verificadas. Werner Moura Ewald (`werner.moura2@gmail.com`) já possui acesso de administrador ativo. A função `ete-admin-users` está ativa, verifica a sessão e a permissão no servidor. O HTML inclui o endereço e a chave pública. O repositório GitHub aguarda a conexão da conta.

O Site atual está privado para seu proprietário. O cadastro de um editor no Supabase não libera a barreira de acesso privada do Site. Para os outros operadores utilizarem o sistema, publique este pacote no GitHub Pages ou ajuste explicitamente o compartilhamento da hospedagem. A autenticação e as permissões do banco continuam protegendo os registros.

## Instalação no Supabase

1. Neste projeto, o SQL já está aplicado: não é necessário executá-lo de novo. Para instalar em outro projeto, execute todos os arquivos de `supabase/migrations` na ordem do nome, ou use o arquivo combinado `Banco_AMESC_ETE.sql`.
2. Em Authentication → Users, crie o primeiro usuário com email e senha. Desative o cadastro público em Authentication → Providers → Email → Allow new users to sign up.
3. Copie `supabase/02_primeiro_administrador.sql`, substitua `SEU_EMAIL_AQUI` pelo email criado e execute. Não coloque senha no SQL.
4. A função `supabase/functions/ete-admin-users/index.ts` já foi publicada neste projeto. Para uma nova instalação, publique com a configuração de `supabase/config.toml`, mantendo `verify_jwt = true`. Ela verifica a sessão com `auth.getUser(token)` e confere a permissão de administrador antes de criar uma conta. As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas no ambiente da função, nunca no HTML.
5. O endereço e a chave **publishable** já estão incluídos neste HTML. Se o projeto mudar, atualize com `configurar_html.py --url https://SEU-PROJETO.supabase.co --publishable-key SUA_CHAVE_PUBLICA`. A configuração incluída no arquivo vale para todos os usuários do HTML publicado.
6. Entre com o primeiro administrador. Em **Usuários**, cadastre os demais usuários. O cadastro é direto; o sistema não envia emails de convite. A senha inicial tem no mínimo 8 caracteres e precisa atender às regras de senha do projeto.

## Hospedagem no GitHub

Crie ou use o repositório `amesc-ete`, com estes arquivos na raiz. Em Settings → Pages, escolha **GitHub Actions**. O fluxo `.github/workflows/pages.yml` publica apenas o HTML, o manifesto, o service worker e os ícones; arquivos SQL e função não são enviados ao site. Depois do envio ao branch `main`, confirme o resultado do workflow e use a URL retornada pelo GitHub Pages. A disponibilidade de Pages em um repositório privado depende do plano da conta.

O HTML distribuído neste pacote inicia sem laudos de exemplo nem dados dos documentos enviados. O endereço do Supabase e a chave publishable podem ficar no repositório. Senhas de usuários, chave secreta e arquivos de documentos não devem ficar nele.

## Usar os registros anteriores

Antes de conectar, no HTML atual clique em **Guardar cópia** e exporte **todos os anos em JSON**. Após entrar no sistema conectado, clique em **Abrir cópia**, escolha esse JSON, confira a prévia e importe. O banco local fica preservado; não há migração silenciosa. O sistema impede que uma revisão antiga sobrescreva o que outra pessoa acabou de salvar; nesse caso, guarde uma cópia e recarregue os dados.

## Acessos e dados

- **Editor:** cria OS internas, abre novos monitoramentos mensais, registra/edita dias de meses abertos, consulta, imprime e exporta. Não altera OS já avaliadas.
- **Consultar:** leitura, impressão e exportação.
- **Administrador:** aprova/avalia OS, fecha e reabre meses, insere/importa laudos, notas, OS da empresa, MTR e folhas antigas, gerencia usuários e acompanha o crescimento do banco. Também pode fazer os registros permitidos ao editor.

Essas regras são verificadas pelo banco, inclusive se os botões do HTML forem manipulados. Importações de cópias e folhas antigas usam o RPC `ete_import_state`, reservado ao administrador.

O banco guarda o estado estruturado em JSONB, preservando os formatos e registros históricos do HTML. As vistas `ete_daily_readings`, `ete_documents`, `ete_analysis_results` e `ete_product_items` permitem consultas SQL por dia, documento, análise e produto. RLS limita os dados ao espaço de trabalho do usuário. As funções privilegiadas ficam no esquema privado; os RPCs públicos executam como o usuário e chamam essas funções, que verificam a permissão, o fechamento mensal e a revisão dentro da transação. `ete_audit` registra usuário, ação, data e revisão, sem guardar documentos ou senhas.

Os resultados dos laudos aparecem no **dia da coleta**. OS internas aparecem pelo número na coluna depois do dia; OS lidas, MTR e produtos aparecem abaixo da data correspondente. A entrada de produtos usa a data de entrega. CCL padrão: `IN105949`. Responsáveis padrão: Rildo Ramos da Silva e Werner Moura Ewald.

## Instalação no celular

Abra a versão HTTPS no celular, entre e use **Instalar no celular**. No Chrome Android, o botão usa a instalação nativa quando o navegador a disponibiliza; também pode usar o menu → Instalar aplicativo/Adicionar à tela inicial. No iPhone, abra no Safari → Compartilhar → Adicionar à Tela de Início. O ícone abre o sistema como aplicativo. É necessário internet para consultar e salvar os dados do Supabase. O service worker guarda apenas a interface; não guarda respostas do banco, documentos ou tokens. O HTML aberto como arquivo local não pode ser instalado como PWA.

## Crescimento do banco

O menu **Banco de dados**, somente do administrador, mostra bytes das tabelas da ETE (dados, índices, auditoria e histórico), bytes do banco PostgreSQL completo, bytes do JSONB do monitoramento e contagem de meses, dias preenchidos, OS, laudos/resultados, produtos/itens, MTRs e usuários. Espaço das tabelas e banco completo são métricas do projeto; a contagem e o JSONB são do espaço de trabalho selecionado. Não incluem uma estimativa de quota, WAL ou arquivos externos.

`ete_usage_history` guarda uma medição real por dia em UTC. O histórico começou em 11/10/2026. Salvar dados ou abrir o menu atualiza a medição desse dia. O gráfico usa até 366 medições; o resumo tabular mostra até 31. Com apenas uma medição, informa que ainda não há dias suficientes para uma curva. Não há reconstrução de dados anteriores nem medições fictícias.

## Leitura de fotos

PDF com texto, PDF digitalizado, JPG, PNG, WEBP e XML de NF-e são aceitos. A leitura de imagens usa Tesseract no aparelho, com modelos de português e inglês. Fotos sem dados suficientes recebem uma segunda tentativa com contraste ajustado. A inicialização do motor foi corrigida para encerrar o processo e informar falhas no carregamento do modelo. Falhas e demora excessiva são informadas; a tela deixa os campos disponíveis para preenchimento e correção. **Ver texto lido** ajuda a conferir o reconhecimento e desaparece ao fechar a leitura; esse texto não é salvo.

No teste real com a OS amarela, a segunda leitura reconheceu `2181`; a data manuscrita continuou em branco. Na foto da planilha manuscrita enviada em 11/10/2026, o OCR reconheceu títulos impressos, mas a amostra de 18 células não trouxe medições utilizáveis. Foram testados localmente contraste, remoção das linhas e outros modelos de escrita/dígitos; os valores não ficaram confiáveis e esses modelos não foram incluídos na versão publicada. A foto continua visível na tela de conferência para preencher ou corrigir os campos antes de importar. Sempre confira antes de importar. O sistema não inventa resultados, e não promete leitura perfeita de manuscritos. Fotos e PDFs não são enviados ao Supabase nem armazenados; somente campos confirmados são salvos.

## Validação feita

As quatro migrações foram executadas no Supabase real, PostgreSQL 17.11. Foram confirmados o administrador ativo, a leitura do estado e o retorno das medidas de espaço e contagens pelo RPC autenticado. A API real recusa dados e cadastro de usuário sem autenticação.

As migrações passaram em 41 testes PostgreSQL via PGlite, incluindo permissões de editor/administrador, RLS, conflitos, fechamento/reabertura, aprovação de OS, fórmulas, métricas de tamanho e histórico sem valores fabricados. O cliente passou em 14 testes de configuração, login controlado, perfis e importação administrativa. A interface existente passou em 31 verificações de comportamento num harness DOM. Manifesto, ícones, curva de crescimento e escopo do cache passaram em verificações próprias. A função de cadastro passou em testes de JWT explícito, autorização e reversão de cadastro incompleto.

Não houve teste de renderização em navegador, instalação real em um telefone, criação de usuário real pela função ou publicação no GitHub nesta etapa. Esses limites não substituem a verificação dos menus no aparelho utilizado. O verificador de segurança apontou uma configuração de Auth a considerar: [proteção contra senhas vazadas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) desativada. O banco mantém RLS e as verificações de permissões das migrações.
