# Componentes incorporados

O HTML contém bibliotecas de terceiros para funcionar sem carregar um CDN durante a leitura:

- Supabase JS 2.97.0 — MIT — https://github.com/supabase/supabase-js
- Tesseract.js e Tesseract OCR — Apache-2.0 — https://github.com/naptha/tesseract.js e https://github.com/tesseract-ocr/tesseract
- Modelo português tessdata_fast 4.1.0 — Apache-2.0 — https://github.com/tesseract-ocr/tessdata_fast/tree/4.1.0
- PDF.js — Apache-2.0 — https://github.com/mozilla/pdf.js

O adaptador incorporado de Tesseract.js foi modificado para rejeitar a inicialização e encerrar o worker quando o carregamento do modelo ou a inicialização falha, em vez de deixar a promessa pendente.

Os avisos de licença dos bundles são preservados nos assets incorporados. A escolha da licença para o código próprio do sistema fica a cargo do proprietário do repositório.
