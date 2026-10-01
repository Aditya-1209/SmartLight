const compIds = COMPONENT_IDS;
const comps=Object.fromEntries(await Promise.all(Object.entries(compIds).map(async([k,id])=>[k,await figma.getNodeByIdAsync(id)])));
const links=[];
function navTo(node,target){links.push({id:node.id,target});}
function chip(parent,title,active=false,ic){const n=row(parent,'Filter / '+title,96,6,10,active?'raised':null,99);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='AUTO';if(ic)icon(n,ic,active?'mint':'muted',16);text(n,title,12,active?'mint':'muted','Medium');return n;}
function action(parent,label,primary=false,w){return inst(parent,comps[primary?'buttonPrimary':'buttonSecondary'],{Label:label},w);}
function heading(parent,title,sub,width){const n=stack(parent,'Heading',width,4);text(n,title,32,'text','Semi Bold');if(sub)text(n,sub,14,'muted','Regular',width);return n;}
function sectionTitle(parent,title,actionLabel,width){const n=row(parent,title,width,8);grow(text(n,title,20,'text','Semi Bold'));if(actionLabel)text(n,actionLabel,12,'mint','Medium');return n;}
function roomArt(parent,w,h){
 const n=box(parent,'Room illustration',w,h,null);n.clipsContent=true;
 const art=track(figma.createNodeFromSvg('<svg width="400" height="240" viewBox="0 0 400 240" xmlns="http://www.w3.org/2000/svg"><path d="M45 145 194 73 355 149 209 229Z" fill="#25392F"/><path d="M45 48 194 4v69L45 145Z" fill="#30483A"/><path d="M194 4 355 56v93L194 73Z" fill="#25382F"/><path d="m56 52 124-37" stroke="#EDCA93" stroke-width="4" stroke-linecap="round"/><path d="m210 16 130 43" stroke="#EDCA93" stroke-width="4" stroke-linecap="round"/><path d="m56 57 124-37v25L56 83Z" fill="#EDCA93" opacity=".08"/><path d="m210 22 130 43v30L210 51Z" fill="#EDCA93" opacity=".07"/><path d="m115 113 100-30 88 41-101 37Z" fill="#41604A"/><path d="M115 113v35l87 42v-29Z" fill="#36553F"/><path d="m202 161 101-37v34l-101 40Z" fill="#22372A"/><path d="m122 123 78 38 96-35" stroke="#CDBCEF" stroke-width="3" stroke-linecap="round"/><path d="m132 119 23-7 25 12-22 9Zm28-9 23-7 25 12-22 9Z" fill="#7E9278"/><path d="m278 177 31-12 25 13-33 14Z" fill="#475F4B"/><path d="M307 173v-37" stroke="#849880" stroke-width="2"/><path d="M306 146c-21-6-16-23-16-23 21 4 16 23 16 23Zm2 10c20-7 17-24 17-24-20 5-17 24-17 24Z" fill="#6A8D6C"/></svg>'));n.appendChild(art);art.resize(w,h);return n;
}
function roomHero(parent,w,compact=false){const n=stack(parent,'Room brightness',w,12,20,'surface',24);n.fills=gradient('#263B2F','#1B2922');if(compact){n.paddingTop=16;n.paddingBottom=16;}outline(n);const top=row(n,'Room status',w-40,8);grow(text(top,'ROOM BRIGHTNESS',11,'mint','Medium'));const power=row(top,'All lights power',40,0,9,'mint',99);icon(power,'power','ink',20);
 const middle=row(n,'Brightness and illustration',w-40,8);const value=stack(middle,'Current brightness',100,0);text(value,'72%',40,'text','Medium');text(value,'3 lights on',12,'muted');roomArt(middle,w-148,compact?96:114);
 const level=row(n,'Adjust brightness',w-40,12);icon(level,'sun','mint',18);slider(level,w-100,72);return n;}
function light(parent,type='White',name='Wipro Tube 1',detail='Warm white · 3200 K',w=352,summaryOnly=false){const n=inst(parent,comps['light'+type],{Name:name,Detail:detail},w);if(summaryOnly){const summary=n.findOne(x=>x.name==='Brightness summary');if(summary)summary.visible=false;}return n;}
function scene(parent,name,w=170){const n=inst(parent,comps['scene'+name.replaceAll(' ','')],null,w);const art=n.findOne(x=>x.type==='FRAME'&&x.name.startsWith('Atmosphere /'));if(art)art.resize(w,art.height);const caption=n.findOne(x=>x.name==='Scene caption');if(caption){caption.resize(w,caption.height);for(const t of caption.children)if(t.type==='TEXT'){t.textAutoResize='HEIGHT';t.resize(w-28,t.height);}}return n;}
function field(parent,title,value,width){const wrap=stack(parent,title,width,8);text(wrap,title,12,'muted','Medium');const f=row(wrap,'Input / '+title,width,12,16,'raised',12);text(f,value,16,'text','Regular');return f;}
function settingRow(parent,ic,title,sub,w,right){const n=row(parent,title,w,12,16,'surface',16);icon(n,ic,'mint',22);const desc=stack(n,'Setting text',w-108,2);grow(desc);text(desc,title,14,'text','Medium');if(sub)text(desc,sub,12,'muted','Regular',w-108);if(right)text(n,right,12,'muted');else icon(n,'arrow','muted',18);return n;}
function editorContents(parent,w,desktop=false){
 const name=field(parent,'Scene name','Golden hour',w);
 const appearance=row(parent,'Scene appearance',w,12);text(appearance,'Icon',12,'muted','Medium');for(const key of ['sun','moon','book','play','scenes']){const b=row(appearance,key,44,0,11,key==='sun'?'raised':null,12);icon(b,key,key==='sun'?'warm':'muted',22);}
 const start=action(parent,'Use current lights',false,w);text(parent,'Or choose a setting for each light.',12,'muted');
 const expanded=stack(parent,'Wipro Tube 1 settings',w,12,16,'surface',20);outline(expanded);
 const title=row(expanded,'Selected light',w-32,10);icon(title,'check','mint',20);grow(text(title,'Wipro Tube 1',16,'text','Medium'));inst(title,comps.toggleOn);
 labelPair(expanded,'Brightness','35%',w-32);slider(expanded,w-32,35,'warm');
 const choice=row(expanded,'Colour mode',w-32,6);chip(choice,'Keep');chip(choice,'White',true);chip(choice,'Colour');
 labelPair(expanded,'White temperature','3200 K',w-32,12);
 const temp=box(expanded,'Warm to cool slider',w-32,20,null);const ramp=rect(temp,'White temperature track',w-32,6,'warm',3);ramp.y=7;ramp.fills=gradient('#EDBD79','#ADCFF1');const knob=circle(temp,18,'text');knob.x=(w-32)*.3;knob.y=1;
 for(const [label,sub,col]of [['Wipro Tube 2','On · 35% · Warm white','warm'],['Tapo Strip','On · 20% · Soft peach','purple']]){const n=row(parent,label,w,12,16,'surface',16);icon(n,'check','mint',20);const info=stack(n,'Light scene values',w-108,2);grow(info);text(info,label,14,'text','Medium');text(info,sub,12,'muted');icon(n,'arrow','muted',18);}
 text(parent,'Saving a scene won’t change your lights.',12,'muted','Regular',w);
 return {name,start};
}
function linkNav(nav){for(const name of ['My room','Scenes','Settings']){const n=nav.findOne(n=>n.name==='Go to '+name);if(n)navTo(n,name);}}
function phone(page,title,x,active='My room',hasNav=true){
 const frame=stack(page,'Android / '+title,412,0,0,'bg',28);frame.resize(412,915);frame.primaryAxisSizingMode='FIXED';frame.clipsContent=true;frame.x=x;frame.y=160;
 const status=row(frame,'System status',412,8,0);status.resize(412,32);status.counterAxisSizingMode='FIXED';status.paddingLeft=24;status.paddingRight=24;grow(text(status,'9:41',12,'text','Medium'));icon(status,'wifi','text',16);const battery=rect(status,'Battery',20,10,'text',3);
 const view=box(frame,'Scrollable content',412,hasNav?791:799,null);view.overflowDirection='VERTICAL';view.clipsContent=true;
 const content=stack(view,'Screen content',412,24,20);content.paddingBottom=28;
 if(hasNav){const nav=inst(frame,comps['nav'+active.replaceAll(' ','')],null,412);nav.resize(412,92);nav.counterAxisSizingMode='FIXED';linkNav(nav);}else{const footer=row(frame,'Save actions',412,12,16,'surface');footer.resize(412,84);footer.counterAxisSizingMode='FIXED';const cancel=action(footer,'Cancel',false,108);navTo(cancel,'Scenes');const save=action(footer,'Save scene',true,256);navTo(save,'Saved scene');}
 return {frame,content};
}
