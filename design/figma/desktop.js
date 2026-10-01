const page=await figma.getNodeByIdAsync('2:3');await figma.setCurrentPageAsync(page);
const title=text(page,'SmartLight / Mac & Windows',40,'text','Medium');title.x=120;title.y=48;
const roots={},navlinks=[];
function desktop(platform,view,x,y){
 const frame=stack(page,platform+' / '+view,1440,0,0,'bg',16);frame.resize(1440,1000);frame.primaryAxisSizingMode='FIXED';frame.clipsContent=true;frame.x=x;frame.y=y;
 const chrome=row(frame,platform+' window controls',1440,8,0,'surface');chrome.resize(1440,38);chrome.counterAxisSizingMode='FIXED';chrome.paddingLeft=20;chrome.paddingRight=20;
 if(platform==='Mac'){for(const c of ['#E69C91','#E7C687','#9BC7A6'])circle(chrome,10,c);const app=text(chrome,'SmartLight',12,'muted','Medium');app.layoutSizingHorizontal='FILL';app.textAlignHorizontal='CENTER';}else{grow(text(chrome,'SmartLight',12,'muted','Medium'));text(chrome,'—    □    ×',14,'muted');}
 const shell=row(frame,'App shell',1440,0);shell.resize(1440,962);shell.counterAxisSizingMode='FIXED';shell.counterAxisAlignItems='MIN';
 const side=stack(shell,'Sidebar',224,32,20,'surface');side.resize(224,962);side.primaryAxisSizingMode='FIXED';
 const brand=row(side,'Brand',184,10,0);icon(brand,'bulb','mint',26);text(brand,'SmartLight',20,'text','Semi Bold');
 const nav=stack(side,'Navigation',184,8);for(const name of ['My room','Scenes','Settings']){const ni=inst(nav,comps['side'+name.replaceAll(' ','')+(view==='My room'?name==='My room':name==='Scenes')]);navlinks.push({node:ni,platform,target:name});}
 const space=box(side,'Flexible space',184,100,null);space.layoutSizingVertical='FILL';
 const footer=stack(side,'Connection status',184,8,14,'raised',16);dotBadge(footer,'Local connection');text(footer,'On your home Wi-Fi',12,'muted');
 const main=stack(shell,'Main content',1216,28,40);main.resize(1216,962);main.primaryAxisSizingMode='FIXED';main.clipsContent=true;
 return {frame,main};
}
function room(platform,x,y){const s=desktop(platform,'My room',x,y);s.main.itemSpacing=20;roots[platform+' room']=s.frame;
 const head=row(s.main,'Room heading',1136,24);const words=stack(head,'Heading',800,4);grow(words);text(words,'YOUR SPACE',11,'muted','Medium');text(words,'My room.',32,'text','Semi Bold');text(words,'Just the right light for right now.',14,'muted');dotBadge(head,'3 connected');
 const upper=row(s.main,'Room controls',1136,24);upper.counterAxisAlignItems='MIN';
 const hero=stack(upper,'Room brightness',708,12,24,'surface',24);hero.fills=gradient('#2B4233','#182920');outline(hero);
 const herohead=row(hero,'Room brightness label',652,12);grow(text(herohead,'ROOM BRIGHTNESS',11,'mint','Medium'));const allpower=row(herohead,'All lights power',112,8,10,'mint',99);icon(allpower,'power','ink',18);text(allpower,'All on',14,'ink','Medium');
 const middle=row(hero,'Room atmosphere',652,16);const value=stack(middle,'Brightness readout',160,4);text(value,'72%',56,'text','Medium');text(value,'Warm, easy light.',14,'muted');roomArt(middle,430,108);const track=row(hero,'Room dimmer',652,16);icon(track,'sun','mint',22);slider(track,592,72);
 const quick=stack(upper,'Quick mood',404,16,24,'surface',24);outline(quick);text(quick,'Make it a moment.',20,'text','Semi Bold');const tiles=row(quick,'Favourite scenes',356,16);scene(tiles,'Golden hour');scene(tiles,'Movie');
 sectionTitle(s.main,'Your lights','3 devices',1136);const lights=row(s.main,'Connected lights',1136,24);light(lights,'White','Wipro Tube 1','Warm white · 3200 K',362);light(lights,'White','Wipro Tube 2','Warm white · 3200 K',362);light(lights,'Colour','Tapo Strip','Soft lavender · Colour',362);
 sectionTitle(s.main,'A scene for every mood','View all scenes  →',1136);const sr=row(s.main,'Scenes',1136,16);for(const name of ['Study','Movie','Chill','Sleep'])scene(sr,name,272);
 return s;
}
function scenes(platform,x,y,editing=false){const s=desktop(platform,editing?'New scene':'Scenes',x,y);roots[platform+(editing?' editor':' scenes')]=s.frame;
 const header=row(s.main,'Scene heading',1136,24);const words=stack(header,'Heading',830,4);grow(words);text(words,editing?'Make it your own.':'Set the mood.',40,'text','Medium');text(words,editing?'A custom scene, down to the last light.':'Save a feeling. Come back to it in one tap.',14,'muted');const add=action(header,editing?'Back to scenes':'+ New scene',!editing,176);navlinks.push({node:add,platform,target:editing?'Scenes':'Editor'});
 if(!editing){
 const filter=row(s.main,'Filters',1136,8);chip(filter,'All scenes',true);chip(filter,'My scenes');chip(filter,'Presets');
 const grid=row(s.main,'Scene gallery and detail',1136,32);grid.counterAxisAlignItems='MIN';const gallery=stack(grid,'Scene collection',704,24);text(gallery,'MADE BY YOU',11,'muted','Medium');const c=row(gallery,'My scenes',704,20);scene(c,'Golden hour',221);scene(c,'Reading',221);const newtile=stack(c,'Create scene tile',221,14,20,'surface',20);newtile.resize(221,158);newtile.primaryAxisSizingMode='FIXED';newtile.counterAxisAlignItems='CENTER';newtile.primaryAxisAlignItems='CENTER';outline(newtile);icon(newtile,'plus','mint',26);text(newtile,'Create a scene',14,'mint','Medium');navlinks.push({node:newtile,platform,target:'Editor'});
 sectionTitle(gallery,'Everyday favourites',null,704);for(const pair of [['Study','Movie','Chill'],['Sleep']]){const rr=row(gallery,'Presets',704,20);for(const name of pair)scene(rr,name,221);}
 const preview=stack(grid,'Golden hour preview',400,20,24,'surface',24);outline(preview);const top=row(preview,'Preview heading',352,12);grow(text(top,'Golden hour',24,'text','Semi Bold'));icon(top,'sun','warm',24);text(preview,'YOUR SCENE',11,'warm','Medium');roomArt(preview,352,188);text(preview,'A warmer room. A slower evening.',14,'muted','Regular',352);for(const [name,detail]of [['Wipro Tube 1','35% · Warm white'],['Wipro Tube 2','35% · Warm white'],['Tapo Strip','20% · Soft peach']]){const r=stack(preview,name,352,4);text(r,name,14,'text','Medium');text(r,detail,12,'muted');}action(preview,'Apply scene',true,352);const edit=action(preview,'Edit scene',false,352);navlinks.push({node:edit,platform,target:'Editor'});
 }else{
 const columns=row(s.main,'Scene editor and live summary',1136,32);columns.counterAxisAlignItems='MIN';const form=stack(columns,'Scene form',680,20,24,'surface',24);outline(form);
 const meta=row(form,'Scene name and appearance',632,24);field(meta,'Scene name','Golden hour',300);const appearance=stack(meta,'Scene appearance',308,8);text(appearance,'Icon',12,'muted','Medium');const icons=row(appearance,'Icon choice',308,12);for(const key of ['sun','moon','book','play','scenes']){const b=row(icons,'Icon / '+key,44,0,11,key==='sun'?'raised':null,12);icon(b,key,key==='sun'?'warm':'muted',22);}const fillCurrent=action(form,'Use current lights',false,632);
 const included=row(form,'Included lights',632,12);for(const name of ['Wipro Tube 1','Wipro Tube 2','Tapo Strip']){const pill=row(included,name,202,10,12,'raised',12);icon(pill,'check','mint',18);text(pill,name,14,'text','Medium');}
 const panel=stack(form,'Selected light controls',632,16,20,'bg',20);const h=row(panel,'Light heading',592,12);grow(text(h,'Wipro Tube 1',20,'text','Semi Bold'));inst(h,comps.toggleOn);labelPair(panel,'Brightness','35%',592);slider(panel,592,35,'warm');const mode=row(panel,'Light mode',592,8);chip(mode,'Keep');chip(mode,'White',true);chip(mode,'Colour');labelPair(panel,'White temperature','3200 K',592);const temp=box(panel,'White temperature',592,28,null);const ramp=rect(temp,'Temperature track',592,6,'warm',3);ramp.y=11;ramp.fills=gradient('#EDBD79','#ADCFF1');const handle=circle(temp,22,'text');handle.x=168;handle.y=3;labelPair(panel,'Warm','Cool',592,12);
 const footer=row(form,'Editor footer',632,12);grow(text(footer,'Saving won’t change your lights.',12,'muted'));const cancel=action(footer,'Cancel',false,96);navlinks.push({node:cancel,platform,target:'Scenes'});const save=action(footer,'Save scene',true,140);navlinks.push({node:save,platform,target:'Scenes'});
 const preview=stack(columns,'Scene summary',424,24,24,'surface',24);outline(preview);text(preview,'THE FEELING',11,'warm','Medium');text(preview,'Golden hour',32,'text','Semi Bold');roomArt(preview,376,220);for(const [name,value]of [['Wipro Tube 1','35% · Warm white'],['Wipro Tube 2','35% · Warm white'],['Tapo Strip','20% · Soft peach']]){const r=stack(preview,name,376,4);text(r,name,16,'text','Medium');text(r,value,12,'muted');}text(preview,'3 lights · Saved on this device',12,'muted');
 }
 return s;
}
const mac=room('Mac',120,160);scenes('Mac',1680,160);scenes('Mac',3240,160,true);
const windows=room('Windows',120,1300);scenes('Windows',1680,1300);scenes('Windows',3240,1300,true);
for(const link of navlinks){const target=roots[link.platform+(link.target==='My room'?' room':link.target==='Editor'?' editor':link.target==='Settings'?' settings':' scenes')];if(!target)continue;let root=link.node;while(root.parent&&root.parent.type!=='PAGE')root=root.parent;if(root.id===target.id)continue;await link.node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:target.id,navigation:'NAVIGATE',transition:{type:'DISSOLVE',duration:.18,easing:{type:'EASE_OUT'}}}]}]);}
page.flowStartingPoints=[{nodeId:mac.frame.id,name:'Mac · SmartLight'},{nodeId:windows.frame.id,name:'Windows · SmartLight'}];figma.viewport.scrollAndZoomIntoView([mac.frame]);
return {createdNodeIds:[...new Set([...affected,...Object.values(roots).flatMap(allIds)])],mutatedNodeIds:[page.id],screens:Object.fromEntries(Object.entries(roots).map(([k,v])=>[k,evidence(v)]))};
