const page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);
const masters=stack(page,'Component masters',1120,24,32,'bg',24);masters.x=1600;masters.y=120;
const comps={};
for(const kind of ['Primary','Secondary']){
 const n=row(masters,'Button',180,8,12,kind==='Primary'?'mint':'raised',16);n.primaryAxisAlignItems='CENTER';n.paddingLeft=20;n.paddingRight=20;
 const t=text(n,'Save scene',14,kind==='Primary'?'ink':'text','Semi Bold');const c=component(n,'Button / '+kind);c.paddingTop=14;c.paddingBottom=14;setTextProperty(c,t,'Label');comps['button'+kind]=c;
}
for(const state of ['On','Off']){
 const n=row(masters,'Toggle',48,0,4,state==='On'?'mint':'line',99);n.resize(48,28);n.primaryAxisSizingMode='FIXED';n.primaryAxisAlignItems=state==='On'?'MAX':'MIN';circle(n,20,state==='On'?'ink':'muted');comps['toggle'+state]=component(n,'Toggle / '+state);
}
for(const type of ['White','Colour','Offline']){
 const n=stack(masters,'Light',352,12,16,'surface',20);outline(n);
 const top=row(n,'Light identity',320,12);
 const glyph=row(top,'Device',44,0,11,'raised',12);icon(glyph,type==='Colour'?'strip':'tube',type==='Offline'?'muted':type==='Colour'?'purple':'warm',22);
 const identity=stack(top,'Identity',200,2);grow(identity);const title=text(identity,'Wipro Tube 1',16,'text','Medium');const detail=text(identity,type==='Offline'?'Not reachable':'Warm white · 3200 K',12,'muted');
 inst(top,comps[type==='Offline'?'toggleOff':'toggleOn']);
 const lower=row(n,'Brightness summary',320,12);if(type==='Offline'){text(lower,'Last seen 5 min ago',12,'muted');}else{slider(lower,240,type==='Colour'?45:72,type==='Colour'?'purple':'warm');text(lower,type==='Colour'?'45%':'72%',14,'text','Medium');}
 const c=component(n,'Light card / '+type);setTextProperty(c,title,'Name');setTextProperty(c,detail,'Detail');comps['light'+type]=c;
}
const sceneDefs=[['Golden hour','warm','#403125','#211E1A','sun','3 lights · Warm & low'],['Study','blue','#293A3C','#172327','book','3 lights · Clear & bright'],['Movie','purple','#3C304C','#221F30','play','3 lights · Soft & cinematic'],['Chill','mint','#23423B','#172721','scenes','3 lights · Unwind'],['Sleep','blue','#26304A','#171E2C','moon','3 lights · Wind down'],['Reading','warm','#493729','#282218','book','2 lights · Your scene']];
for(const [name,color,a,b,ic,detail] of sceneDefs){
 const n=stack(masters,'Scene',170,0,0,'surface',20);n.clipsContent=true;outline(n);
 const art=box(n,'Atmosphere / '+name,170,88,null);art.fills=gradient(a,b);art.clipsContent=true;
 const halo=circle(art,112,color);halo.x=100;halo.y=28;halo.opacity=.09;
 const halo2=circle(art,84,color);halo2.x=114;halo2.y=42;halo2.opacity=.09;
 const glyph=icon(art,ic,color,28);glyph.x=16;glyph.y=18;
 const line=rect(art,'Light beam',88,2,color,1);line.x=54;line.y=62;line.opacity=.65;
 const body=stack(n,'Scene caption',170,4,14);const title=text(body,name,16,'text','Medium');const sub=text(body,detail,11,'muted','Medium',142);
 const c=component(n,'Scene card / '+name);for(const child of c.children)child.layoutSizingHorizontal='FILL';setTextProperty(c,title,'Name');setTextProperty(c,sub,'Detail');comps['scene'+name.replaceAll(' ','')]=c;
}
for(const active of ['My room','Scenes','Settings']){
 const n=row(masters,'Navigation',392,0,8,'surface');n.paddingBottom=14;n.paddingTop=12;
 for(const [name,ic]of [['My room','room'],['Scenes','scenes'],['Settings','settings']]){
  const cell=stack(n,'Go to '+name,125,4);cell.counterAxisAlignItems='CENTER';
  const hit=row(cell,'Tab target',60,0,10,name===active?'raised':null,16);hit.primaryAxisAlignItems='CENTER';icon(hit,ic,name===active?'mint':'muted',22);
  text(cell,name,11,name===active?'mint':'muted','Medium');
 }
 comps['nav'+active.replaceAll(' ','')]=component(n,'Mobile navigation / '+active);
}
for(const name of ['My room','Scenes','Settings'])for(const active of [true,false]){
 const n=row(masters,'Sidebar item',184,12,14,active?'raised':null,12);icon(n,name==='My room'?'room':name==='Scenes'?'scenes':'settings',active?'mint':'muted',20);text(n,name,14,active?'mint':'muted','Medium');comps['side'+name.replaceAll(' ','')+active]=component(n,'Sidebar / '+name+' / '+(active?'Active':'Default'));
}
const board=stack(page,'SmartLight / Foundations',1280,32,48,'bg',24);board.x=120;board.y=120;
const brand=row(board,'Brand',1184,12);icon(brand,'bulb','mint',32);text(brand,'SmartLight',24,'text','Semi Bold');
text(board,'A little light.\nA room that feels like you.',40,'text','Medium',900);
text(board,'UI direction · 01 October 2026 · Android, macOS & Windows',14,'muted');
const palette=row(board,'Colour palette',1184,16);
for(const name of ['bg','surface','raised','mint','warm','purple','blue']){const sw=stack(palette,'Colour / '+name,148,8);rect(sw,name,148,56,name,12);text(sw,name,14,'text','Medium');text(sw,C[name],12,'muted');}
const sample=row(board,'Controls',1184,24);inst(sample,comps.buttonPrimary);inst(sample,comps.buttonSecondary,{Label:'Use current lights'});inst(sample,comps.toggleOn);inst(sample,comps.toggleOff);dotBadge(sample,'Connected');
const cards=row(board,'Reusable components',1184,20);inst(cards,comps.lightWhite);inst(cards,comps.lightOffline);inst(cards,comps.sceneGoldenhour);inst(cards,comps.sceneMovie);
const principles=row(board,'Design notes',1184,32);
for(const [title,body]of [['Room first','Room controls, individual lights, then scenes. Keep setup and diagnostics in Settings.'],['Colour with purpose','Mint means action. Warmth and colour reflect the light. A label always explains the state.'],['Made to resize','Inter type, 8-point spacing, 48 px primary targets. Desktop panels become stacked phone cards.']]){const note=stack(principles,title,370,8);text(note,title,20,'text','Semi Bold');text(note,body,14,'muted','Regular',354);}
text(board,'Prototype values are illustrative. No saved connection, pairing, or device state is changed by this design.',12,'muted');
return {createdNodeIds:[...new Set([...affected,...allIds(masters),...allIds(board)])],components:Object.fromEntries(Object.entries(comps).map(([k,v])=>[k,v.id])),board:evidence(board),masters:masters.id};
