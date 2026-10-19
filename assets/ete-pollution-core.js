'use strict';
globalThis.ETEPollutionCore=(()=>{
 const SCHEMA='ete-pollution-v1',MONTHS=['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
 const PARAMETERS=[
  {key:'dboIn',label:'DBOa',title:'DBO de entrada',side:'in'},
  {key:'rnftIn',label:'RNFTa',title:'RNFT de entrada',side:'in'},
  {key:'dboOut',label:'DBOe',title:'DBO de saída',side:'out'},
  {key:'rnftOut',label:'RNFTe',title:'RNFT de saída',side:'out'},
  {key:'oilOut',label:'OG v(e)',title:'Óleos e graxas de saída',side:'out'},
  {key:'mbasOut',label:'MBAS (e)',title:'MBAS de saída',side:'out'},
  {key:'codOut',label:'DQO',title:'DQO de saída',side:'out'},
  {key:'ammoniaOut',label:'Nitrogênio Amoniacal',title:'Nitrogênio amoniacal de saída',side:'out'},
  {key:'phosphorusOut',label:'Fósforo Total',title:'Fósforo total de saída',side:'out'}
 ];
 const KEYS=PARAMETERS.map(p=>p.key),clone=x=>JSON.parse(JSON.stringify(x));
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const fold=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 function numeric(value){const s=String(value??'').trim().replace(/\s*(?:mg\s*\/\s*l|kg\s*\/\s*dia|m[³3]\s*\/\s*dia|%)\s*$/i,'');if(!/^-?(?:\d+(?:[.,]\d+)?|[.,]\d+)$/.test(s))return null;const n=Number(s.replace(',','.'));return Number.isFinite(n)&&Math.abs(n)<=1e9?n:null;}
 const mean=values=>{const nums=values.filter(x=>typeof x==='number'&&Number.isFinite(x));return nums.length?nums.reduce((a,b)=>a+b,0)/nums.length:null;};
 const sd=values=>{const a=values.filter(x=>typeof x==='number'&&Number.isFinite(x));if(a.length<2)return null;const avg=mean(a);return Math.sqrt(a.reduce((sum,x)=>sum+(x-avg)**2,0)/(a.length-1));};
 const fmt=(n,digits=2)=>n==null||!Number.isFinite(n)?'—':new Intl.NumberFormat('pt-BR',{minimumFractionDigits:digits,maximumFractionDigits:digits}).format(n);
 const dateText=s=>/^\d{4}-\d{2}-\d{2}$/.test(s||'')?s.slice(8,10)+'/'+s.slice(5,7)+'/'+s.slice(0,4):s||'';
 function validDate(s){if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(s))return false;const [y,m,d]=s.split('-').map(Number);return y>=1900&&y<=2200&&m>=1&&m<=12&&d>=1&&d<=new Date(Date.UTC(y,m,0)).getUTCDate();}
 const lastDate=(y,m)=>String(y)+'-'+String(m).padStart(2,'0')+'-'+new Date(Date.UTC(y,m,0)).getUTCDate();
 function bounds(type,year,month,start,end){const y=Number(year),m=Number(month);if(type==='year'){start=y+'-01-01';end=y+'-12-31';}else if(type==='month'){start=y+'-'+String(m).padStart(2,'0')+'-01';end=lastDate(y,m);}if(!validDate(start)||!validDate(end)||end<start)throw new Error('Escolha um período válido.');return {start,end,days:Math.round((Date.parse(end+'T00:00:00Z')-Date.parse(start+'T00:00:00Z'))/86400000)+1,key:type==='year'?String(y):type==='month'?start.slice(0,7):'',label:type==='year'?String(y):type==='month'?MONTHS[m-1]+' de '+y:dateText(start)+' a '+dateText(end),type};}
 function shiftedYear(date){const [y,m,d]=date.split('-').map(Number);return (y-1)+'-'+String(m).padStart(2,'0')+'-'+String(Math.min(d,new Date(Date.UTC(y-1,m,0)).getUTCDate())).padStart(2,'0');}
 function text(v,max=1000){if(v==null)return '';if(typeof v!=='string'&&typeof v!=='number')throw new Error('Texto inválido nos dados da carga poluidora.');v=String(v);if(v.length>max)throw new Error('Texto muito extenso nos dados da carga poluidora.');return v;}
 function reading(v,field){const value=text(v,80).trim();if(value&&/^[<>≤≥]/.test(value)&&!(/^[<>≤≥]\s*[0-9]+([.,][0-9]+)?(\s*mg\s*\/\s*[Ll])?$/.test(value)))throw new Error('Confira o valor de '+field+'.');if(value&&!/^[<>≤≥]/.test(value)){const n=numeric(value);if(n==null||n<0||(field==='phOut'&&n>14))throw new Error('Confira o valor de '+field+'.');}return value;}
 function canonical(input){
  if(!input||input.schema!==SCHEMA||input.version!==1||!input.records||typeof input.records!=='object'||Array.isArray(input.records))throw new Error('Cópia da carga poluidora incompatível.');
  if(Object.keys(input.records).length>20000||JSON.stringify(input).length>10485760)throw new Error('A cópia excede o tamanho permitido.');
  const check=x=>{if(!x||typeof x!=='object')return;for(const [k,v] of Object.entries(x)){if(['__proto__','constructor','prototype','image','base64','pdfData','fileData','ocrText','rawText'].includes(k))throw new Error('A cópia deve conter somente os dados, sem fotos ou PDFs.');check(v);}};check(input);
  if(Object.keys(input).some(k=>!['schema','version','records'].includes(k)))throw new Error('Campo desconhecido na cópia.');
  const out={schema:SCHEMA,version:1,records:{}};
  for(const [id,raw] of Object.entries(input.records)){
   if(!/^[-a-zA-Z0-9_:.]{1,120}$/.test(id)||['__proto__','constructor','prototype'].includes(id)||raw.id!==id||!['analysis','declaration','config'].includes(raw.kind)||!raw.data||typeof raw.data!=='object'||Array.isArray(raw.data))throw new Error('Registro da carga poluidora inválido.');
   const record=clone(raw),data=record.data;
   if(raw.kind==='analysis'){
    if(!validDate(data.date))throw new Error('Data da análise inválida.');
    for(const k of ['flowIn','flowOut','referenceRNFT','referenceDBO','quantity1','quantity2','quantityTotal','referenceDBOLowLoad'])data[k]=reading(data[k],k);
    data.report=text(data.report,400);data.composed=text(data.composed,80);data.values??={};
    if(typeof data.values!=='object'||Array.isArray(data.values))throw new Error('Parâmetros da análise inválidos.');
    if(Object.keys(data.values).some(k=>![...KEYS,'phOut'].includes(k)))throw new Error('Parâmetro desconhecido.');
    for(const key of [...KEYS,'phOut'])if(key in data.values)data.values[key]=reading(data.values[key],key);
   }else if(raw.kind==='declaration'){
    if(!/^\d{4}(-\d{2})?$/.test(data.period||'')||!validDate(data.period+(data.period.length===4?'-01-01':'-01'))||!Array.isArray(data.parameters)||data.parameters.length>30)throw new Error('Declaração importada inválida.');
    if(new Set(data.parameters.map(p=>p.key)).size!==data.parameters.length)throw new Error('Parâmetro duplicado na declaração.');
    for(const p of data.parameters){if(!KEYS.includes(p.key)||!Number.isInteger(p.days)||p.days<1||p.days>366)throw new Error('Parâmetro ou número de dias inválido.');for(const key of ['flow','concentration','tons'])p[key]=reading(p[key],key);}
   }else{
    if(id!=='settings')throw new Error('Identificação dos dados da empresa inválida.');
    for(const [key,value] of Object.entries(data))if(!['source','sources'].includes(key))data[key]=text(value,1000);
   }
   out.records[id]=record;
  }
  return out;
 }
 function parameterKey(raw){const s=fold(raw).replace(/[()]/g,' ').replace(/\s+/g,' ').trim();if(/solidos?\s+sediment|cloro residual/.test(s))return null;if(/\bdbo\b|demanda bioquimica/.test(s))return 'dbo';if(/\brnft\b|\bsst\b|solidos? suspensos|residuo[s]? nao filtrav/.test(s))return 'rnft';if(/\bdqo\b|demanda quimica/.test(s))return 'cod';if(/nitrogenio amoniacal|amonia/.test(s))return 'ammonia';if(/fosforo total/.test(s))return 'phosphorus';if(/oleos.*graxas|graxas.*oleos/.test(s))return 'oil';if(/\bmbas\b|surfactante/.test(s))return 'mbas';if(/^ph\b/.test(s))return 'ph';return null;}
 function pointSide(point){const s=fold(point);if(/\bentrada\b/.test(s)&&/\bete\b/.test(s))return 'in';if(/saida.*\bete\b|\bete\b.*saida|clorador/.test(s)&&!/\brafa\b|\breator\b|\bfiltro\b/.test(s))return 'out';return null;}
 function flowReadings(main,start,end,side){const values=[];for(const [key,m] of Object.entries(main?.months||{}))for(const [d,r] of Object.entries(m.records||{})){const date=key+'-'+String(d).padStart(2,'0');if(date<start||date>end)continue;let value=null;if(side==='in'){const b=numeric(r.balde);if(b!=null&&b>=0)value=b*5.76;else {const h=numeric(r.calhaEntrada);if(h!=null&&h>=0)value=434.58*(h/100)**1.55*24;}}else{const h=numeric(r.calhaSaida);if(h!=null&&h>=0)value=434.58*(h/100)**1.55*24;}if(value!=null)values.push(value);}return values;}
 function loadRows(bundle,main={}){
  const all=Object.values(bundle.records),rows=all.filter(r=>r.kind==='analysis').map(r=>({...clone(r.data),id:r.id,type:'analysis',origin:'imported'})),groups=new Map();
  for(const report of Object.values(main.reports||{})){
   const side=pointSide(report.samplePoint);if(!side||!validDate(report.collectionDate))continue;
   const data=groups.get(report.collectionDate)||{date:report.collectionDate,reports:[],numbers:{},raw:{},sources:[]};
   const perReport={};
   for(const p of report.results||[]){const key=parameterKey(p.parameter);if(!key||(side==='in'&&!['dbo','rnft'].includes(key)))continue;const target=key+(side==='in'?'In':'Out');if(perReport[target]!==undefined)continue;perReport[target]=p.value;}
   for(const [key,value] of Object.entries(perReport)){const n=numeric(value);if(n!=null)(data.numbers[key]??=[]).push(n);(data.raw[key]??=[]).push(String(value));}
   if(Object.keys(perReport).length){data.reports.push(report.number||report.id);data.sources.push({id:report.id,point:report.samplePoint});groups.set(report.collectionDate,data);}
  }
  for(const [date,data] of groups){
   const old=rows.find(r=>r.date===date),values={...(old?.values||{})};
   for(const [key,raw] of Object.entries(data.raw)){const n=mean(data.numbers[key]||[]);values[key]=n==null?raw.join(' / '):String(n);}
   const row={...old,id:old?.id||'live-'+date,date,type:'analysis',origin:'live',report:[...new Set([old?.report,...data.reports].filter(Boolean))].join('; '),composed:old?.composed||'',values,flowIn:String(mean(flowReadings(main,date,date,'in'))??old?.flowIn??''),flowOut:String(mean(flowReadings(main,date,date,'out'))??old?.flowOut??''),source:{label:'Laudos cadastrados no monitoramento',reports:data.sources}};
   if(old)rows.splice(rows.indexOf(old),1,row);else rows.push(row);
  }
  return rows.sort((a,b)=>(a.date+a.id).localeCompare(b.date+b.id));
 }
 function periodRows(bundle,main,period){
  const rows=loadRows(bundle,main).filter(r=>r.date>=period.start&&r.date<=period.end),monthsWithSamples=new Set(rows.map(r=>r.date.slice(0,7)));
  for(const rec of Object.values(bundle.records).filter(r=>r.kind==='declaration'&&r.data.period.length===7)){
   const key=rec.data.period,start=key+'-01',end=lastDate(Number(key.slice(0,4)),Number(key.slice(5,7)));
   if(start<period.start||end>period.end||monthsWithSamples.has(key))continue;
   const values=Object.fromEntries(rec.data.parameters.map(p=>[p.key,p.concentration]));
   rows.push({id:rec.id,type:'monthly',origin:'declaration',date:end,period:key,report:'Média mensal',composed:'',values,flowIn:rec.data.parameters.find(p=>p.key==='dboIn')?.flow||'',flowOut:rec.data.parameters.find(p=>p.key==='dboOut')?.flow||'',source:rec.data.source,referenceRNFT:'',referenceDBO:''});
  }
  return rows.sort((a,b)=>(a.date+a.id).localeCompare(b.date+b.id));
 }
 const kg=(flow,concentration)=>flow==null||concentration==null?null:flow*concentration/1000;
 const efficiency=(a,b)=>a==null||b==null||a===0?null:(a-b)/a*100;
 function deriveRows(bundle,main,period){
  const historyPeriod={start:'1900-01-01',end:period.end},history=periodRows(bundle,main,historyPeriod),selected=periodRows(bundle,main,period);
  const rollingCache=new Map(),rollingAt=date=>{if(!rollingCache.has(date)){const start=shiftedYear(date),slice=history.filter(r=>r.date>start&&r.date<=date),m=key=>mean(slice.map(r=>numeric(r.values[key])));rollingCache.set(date,{dbo:efficiency(m('dboIn'),m('dboOut')),rnft:efficiency(m('rnftIn'),m('rnftOut'))});}return rollingCache.get(date);};
  return selected.map(row=>{
   const end=row.date,start=shiftedYear(end),previous=history.filter(r=>r.date>start&&r.date<=end),roll=key=>mean(previous.map(r=>numeric(r.values[key])));
   const dboIn=numeric(row.values.dboIn),dboOut=numeric(row.values.dboOut),rnftIn=numeric(row.values.rnftIn),rnftOut=numeric(row.values.rnftOut),flowIn=numeric(row.flowIn),flowOut=numeric(row.flowOut);
   const w=previous.map(r=>efficiency(numeric(r.values.dboIn),numeric(r.values.dboOut))),x=previous.map(r=>efficiency(numeric(r.values.rnftIn),numeric(r.values.rnftOut)));
   return {...row,flowInNumber:flowIn,flowOutNumber:flowOut,dboLoad:kg(flowIn,dboIn),rnftLoad:kg(flowIn,rnftIn),dboOutLoad:kg(flowOut,dboOut),rnftOutLoad:kg(flowOut,rnftOut),dboEfficiency:efficiency(dboIn,dboOut),rnftEfficiency:efficiency(rnftIn,rnftOut),meanRNFTIn:roll('rnftIn'),meanDBOIn:roll('dboIn'),meanRNFTOut:roll('rnftOut'),meanDBOOut:roll('dboOut'),sdDBOEfficiency:sd(w),sdRNFTEfficiency:sd(x),rollingDBOEfficiency:efficiency(roll('dboIn'),roll('dboOut')),rollingRNFTEfficiency:efficiency(roll('rnftIn'),roll('rnftOut')),sdRollingDBOEfficiency:sd(previous.map(r=>rollingAt(r.date).dbo)),sdRollingRNFTEfficiency:sd(previous.map(r=>rollingAt(r.date).rnft))};
  });
 }
 function declaration(bundle,main,period,useOriginal=false,days=period.days){
  const archived=Object.values(bundle.records).find(r=>r.kind==='declaration'&&r.data.period===period.key);
  if(useOriginal&&archived)return {...clone(archived.data),original:true,periodLabel:period.label,calendarDays:period.days,coverage:period.type==='year'?Number((archived.data.metrics?.sdPeriod||'').match(/\d+/)?.[0]||12):1};
  const rows=periodRows(bundle,main,period),byMonth=new Map();
  for(const row of rows){const key=row.date.slice(0,7);if(!byMonth.has(key))byMonth.set(key,[]);byMonth.get(key).push(row);}
  const monthly=[...byMonth.entries()].map(([month,rs])=>{const archive=Object.values(bundle.records).find(r=>r.kind==='declaration'&&r.data.period===month)?.data;return {values:Object.fromEntries(KEYS.map(k=>[k,mean(rs.map(r=>numeric(r.values[k])))??numeric(archive?.parameters.find(p=>p.key===k)?.concentration)])),flowIn:mean(rs.map(r=>numeric(r.flowIn)))??numeric(archive?.parameters.find(p=>p.key==='dboIn')?.flow),flowOut:mean(rs.map(r=>numeric(r.flowOut)))??numeric(archive?.parameters.find(p=>p.key==='dboOut')?.flow)};});
  const inlet=mean(flowReadings(main,period.start,period.end,'in'))??mean(monthly.map(r=>r.flowIn)),outlet=mean(flowReadings(main,period.start,period.end,'out'))??mean(monthly.map(r=>r.flowOut));
  const parameters=PARAMETERS.map(p=>{const flow=p.side==='in'?inlet:outlet,concentration=mean(monthly.map(m=>m.values[p.key]));return {key:p.key,flow,concentration,days,tons:flow==null||concentration==null?null:flow*concentration*days/1e6};});
  const p=key=>parameters.find(x=>x.key===key),dboSd=sd((period.type==='month'?rows.map(r=>numeric(r.values.dboOut)):monthly.map(r=>r.values.dboOut))),dboMean=p('dboOut').concentration;
  const difference=(a,b)=>a==null||b==null?null:a-b;
  const metrics={dboInKg:kg(inlet,p('dboIn').concentration),rnftInKg:kg(inlet,p('rnftIn').concentration),dboRemovedTons:difference(p('dboIn').tons,p('dboOut').tons),rnftRemovedTons:difference(p('rnftIn').tons,p('rnftOut').tons),dboEfficiency:efficiency(p('dboIn').concentration,dboMean),rnftEfficiency:efficiency(p('rnftIn').concentration,p('rnftOut').concentration),dboOutSd:dboSd,dboOutCV:dboSd==null||dboMean==null||dboMean===0?null:dboSd/dboMean*100};
  return {period:period.key,periodLabel:period.label,parameters,metrics,original:false,calendarDays:period.days,coverage:monthly.length,rowCount:rows.length};
 }
 const parameterTitle=key=>PARAMETERS.find(p=>p.key===key)?.title||key;
 const profile=bundle=>clone(bundle.records.settings?.data||{});
 const sourceText=source=>source?.filename?(source.filename+(source.page?' · página '+source.page:source.sheet?' · aba '+source.sheet+', linha '+source.row:'')):source?.label||'Registro incluído no sistema';
 const tableColumns=[
  ['Data',r=>r.type==='monthly'?MONTHS[Number(r.period.slice(5,7))-1]+'/'+r.period.slice(0,4)+' (média)':dateText(r.date)],
  ['Laudo',r=>r.report||'—'],['Composta',r=>r.composed||'—'],
  ['RNFT entrada (mg/L)',r=>r.values.rnftIn||'—'],['RNFT entrada média 12 meses (mg/L)',r=>fmt(r.meanRNFTIn)],
  ['Vazão entrada (m³/dia)',r=>fmt(r.flowInNumber)],['Carga RNFT entrada (kg/dia)',r=>fmt(r.rnftLoad)],
  ['Referência RNFT (mg/L)',r=>r.referenceRNFT||'—'],
  ['DBO entrada (mg/L)',r=>r.values.dboIn||'—'],['DBO entrada média 12 meses (mg/L)',r=>fmt(r.meanDBOIn)],
  ['Vazão saída (m³/dia)',r=>fmt(r.flowOutNumber)],['Carga DBO entrada (kg/dia)',r=>fmt(r.dboLoad)],
  ['Referência DBO (mg/L)',r=>r.referenceDBO||'—'],
  ['RNFT saída (mg/L)',r=>r.values.rnftOut||'—'],['RNFT saída média 12 meses (mg/L)',r=>fmt(r.meanRNFTOut)],
  ['DBO saída (mg/L)',r=>r.values.dboOut||'—'],['DBO saída média 12 meses (mg/L)',r=>fmt(r.meanDBOOut)],
  ['Quantidade 1 (m³)',r=>r.quantity1||'—'],['Quantidade 2 (m³)',r=>r.quantity2||'—'],['Quantidade total (m³)',r=>r.quantityTotal||'—'],['Referência DBO para menor carga (mg/L)',r=>r.referenceDBOLowLoad||'—'],
  ['pH saída',r=>r.values.phOut||'—'],['Eficiência DBO (%)',r=>fmt(r.dboEfficiency)],['Eficiência RNFT (%)',r=>fmt(r.rnftEfficiency)],
  ['Desvio eficiência DBO (p.p.)',r=>fmt(r.sdDBOEfficiency)],['Desvio eficiência RNFT (p.p.)',r=>fmt(r.sdRNFTEfficiency)],
  ['Eficiência DBO 12 meses (%)',r=>fmt(r.rollingDBOEfficiency)],['Eficiência RNFT 12 meses (%)',r=>fmt(r.rollingRNFTEfficiency)],
  ['Desvio da eficiência média DBO 12 meses (p.p.)',r=>fmt(r.sdRollingDBOEfficiency)],['Desvio da eficiência média RNFT 12 meses (p.p.)',r=>fmt(r.sdRollingRNFTEfficiency)],
  ['DQO saída (mg/L)',r=>r.values.codOut||'—'],['Óleos e graxas saída (mg/L)',r=>r.values.oilOut||'—'],
  ['MBAS saída (mg/L)',r=>r.values.mbasOut||'—'],['Nitrogênio amoniacal saída (mg/L)',r=>r.values.ammoniaOut||'—'],
  ['Fósforo total saída (mg/L)',r=>r.values.phosphorusOut||'—'],['Origem',r=>sourceText(r.source)]
 ];
 function csv(rows){const cell=v=>{let s=String(v??'');if(/^\s*[=+@-]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};return '\uFEFF'+[tableColumns.map(c=>c[0]),...rows.map(r=>tableColumns.map(c=>c[1](r)))].map(r=>r.map(cell).join(';')).join('\r\n');}
 function graphSVG(rows,kind,period){
  const rnft=kind==='rnft',key=rnft?'rnftOut':'dboOut',meanKey=rnft?'meanRNFTOut':'meanDBOOut',refKey=rnft?'referenceRNFT':'referenceDBO',label=rnft?'RNFT':'DBO';
  const W=1100,H=570,L=80,R=1020,T=45,B=420,N=Math.max(rows.length,1),step=(R-L)/N;
  const values=rows.flatMap(r=>[numeric(r.values[key]),r[meanKey],numeric(r[refKey])]).filter(v=>v!=null),loads=rows.map(r=>r.dboLoad).filter(v=>v!=null);
  const limit=Math.max(10,...values)*1.15,loadLimit=Math.max(1,...loads)*1.15,x=i=>L+step*(i+.5),y=v=>B-(B-T)*v/limit,yl=v=>B-(B-T)*v/loadLimit;
  let svg='<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="'+label+' no período '+esc(period.label)+'" viewBox="0 0 '+W+' '+H+'"><rect width="1100" height="570" fill="white"/>';
  for(let i=0;i<=5;i++){const yy=B-(B-T)*i/5;svg+='<path d="M'+L+' '+yy+'H'+R+'" stroke="#e0e7eb"/><text x="'+(L-9)+'" y="'+(yy+4)+'" text-anchor="end" font-size="13" fill="#344b55">'+esc(fmt(limit*i/5,0))+'</text><text x="'+(R+9)+'" y="'+(yy+4)+'" font-size="13" fill="#75569a">'+esc(fmt(loadLimit*i/5,1))+'</text>';}
  svg+='<text x="'+L+'" y="21" font-size="14" fill="#344b55">Concentração (mg/L)</text><text x="'+R+'" y="21" text-anchor="end" font-size="14" fill="#75569a">Carga DBO entrada (kg/dia)</text>';
  const gap=Math.max(1,Math.ceil(N/14));
  rows.forEach((r,i)=>{const v=numeric(r.values[key]);if(v!=null)svg+='<rect x="'+(x(i)-Math.min(28,step*.55)/2)+'" y="'+y(v)+'" width="'+Math.min(28,step*.55)+'" height="'+(B-y(v))+'" fill="#0070c0"><title>'+esc((r.type==='monthly'?r.period:dateText(r.date))+': '+fmt(v)+' mg/L')+'</title></rect>';if(i%gap===0||i===N-1)svg+='<text transform="translate('+x(i)+' '+(B+17)+') rotate(-45)" text-anchor="end" font-size="12" fill="#344b55">'+esc(r.type==='monthly'?r.period.slice(5)+'/'+r.period.slice(0,4):dateText(r.date))+'</text>';});
  const line=(get,color,axis)=>{let path='',on=false;rows.forEach((r,i)=>{const v=get(r);if(v==null){on=false;return;}path+=(on?'L':'M')+x(i)+' '+axis(v)+' ';on=true;});return path?'<path d="'+path+'" fill="none" stroke="'+color+'" stroke-width="2.5"/>':'';};
  svg+=line(r=>r[meanKey],'#d39b00',y)+line(r=>numeric(r[refKey]),'#208349',y)+line(r=>r.dboLoad,'#8064a2',yl);
  rows.forEach((r,i)=>{if(r.dboLoad!=null)svg+='<circle cx="'+x(i)+'" cy="'+yl(r.dboLoad)+'" r="3" fill="#8064a2"/>';});
  const legends=[['#0070c0',label+' saída'],['#d39b00','Média móvel de 12 meses'],['#208349','Referência da planilha'],['#8064a2','Carga DBO entrada']];
  legends.forEach((l,i)=>{const xx=90+(i%2)*470,yy=530+Math.floor(i/2)*23;svg+='<rect x="'+xx+'" y="'+(yy-10)+'" width="22" height="7" fill="'+l[0]+'"/><text x="'+(xx+31)+'" y="'+yy+'" font-size="14" fill="#344b55">'+l[1]+'</text>';});
  return svg+'</svg>';
 }
 return {SCHEMA,MONTHS,PARAMETERS,KEYS,clone,esc,fold,numeric,mean,sd,fmt,dateText,validDate,lastDate,bounds,canonical,parameterKey,pointSide,loadRows,periodRows,deriveRows,declaration,profile,parameterTitle,sourceText,tableColumns,csv,graphSVG,kg,efficiency};
})();
