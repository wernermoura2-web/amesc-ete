"""Inclui somente o endereço público e a chave publishable/anon no HTML."""
import argparse,json,re,base64
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--url',required=True)
parser.add_argument('--publishable-key',required=True)
parser.add_argument('--html',default='index.html')
args=parser.parse_args()
if not re.fullmatch(r'https://[a-zA-Z0-9.-]+',args.url.rstrip('/')):
    parser.error('Use o endereço HTTPS do projeto, sem caminhos ou parâmetros.')
key=args.publishable_key.strip()
role=''
if key.count('.')==2:
    try:
        segment=key.split('.')[1];role=json.loads(base64.urlsafe_b64decode(segment+'='*((-len(segment))%4))).get('role','')
    except (ValueError,KeyError,json.JSONDecodeError):pass
if key.startswith('sb_secret_') or role=='service_role':
    parser.error('Uma chave secreta nunca pode ser incluída no HTML.')
if not key.startswith('sb_publishable_') and role!='anon':
    parser.error('Use uma chave publishable ou anon válida.')
path=Path(args.html);text=path.read_text()
config=json.dumps({'url':args.url.rstrip('/'),'publishableKey':key},ensure_ascii=True).replace('<','\\u003c')
pattern=r'(<script type="application/json" id="ete-config">).*?(</script>)'
if len(re.findall(pattern,text,re.S))!=1:parser.error('Bloco de configuração não encontrado no HTML.')
path.write_text(re.sub(pattern,lambda m:m[1]+config+m[2],text,count=1,flags=re.S))
print('Endereço e chave pública configurados. Nenhuma senha foi gravada.')
