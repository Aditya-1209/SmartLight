// Shared native Figma construction helpers. Run through the Figma Plugin API.
const C = {bg:'#101716',surface:'#192320',raised:'#232F2B',line:'#35433D',text:'#F3F5EF',muted:'#ABB8AE',mint:'#BDE6CE',ink:'#14261C',warm:'#EDCA93',purple:'#CDBCEF',blue:'#AACBEE',red:'#F0ADA4'};
const rgb = h => ({r:parseInt(h.slice(1,3),16)/255,g:parseInt(h.slice(3,5),16)/255,b:parseInt(h.slice(5,7),16)/255});
const variables = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(variables.filter(v=>v.name.startsWith('color/') || v.name.startsWith('space/') || v.name.startsWith('radius/')).map(v=>[v.name,v]));
const styles = Object.fromEntries((await figma.getLocalTextStylesAsync()).map(s=>[s.name,s]));
await Promise.all(['Regular','Medium','Semi Bold','Bold'].map(style=>figma.loadFontAsync({family:'Inter',style})));
const affected = [];
function track(n){affected.push(n.id);return n;}
function paint(key){let p={type:'SOLID',color:rgb(C[key]||key)};return V['color/'+key]?figma.variables.setBoundVariableForPaint(p,'color',V['color/'+key]):p;}
function fill(n,key){n.fills=key?[paint(key)]:[];}
function radius(n,r){n.cornerRadius=r;if(V['radius/'+r])for(const k of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(k,V['radius/'+r]);}
function spacing(n,key,v){n[key]=v;if(V['space/'+v])n.setBoundVariable(key,V['space/'+v]);}
function box(parent,name,w,h,bg='surface',r=0){const n=track(figma.createFrame());n.name=name;n.resize(w,h);fill(n,bg);radius(n,r);if(parent)parent.appendChild(n);return n;}
function stack(parent,name,w,gap=12,pad=0,bg=null,r=0,dir='VERTICAL'){
 const n=track(figma.createAutoLayout(dir));n.name=name;fill(n,bg);n.resize(w,10);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';spacing(n,'itemSpacing',gap);for(const p of ['paddingTop','paddingBottom','paddingLeft','paddingRight'])spacing(n,p,pad);radius(n,r);if(parent)parent.appendChild(n);return n;
}
function row(parent,name,w,gap=12,pad=0,bg=null,r=0){const n=stack(parent,name,w,gap,pad,bg,r,'HORIZONTAL');n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='AUTO';n.counterAxisAlignItems='CENTER';return n;}
function text(parent,value,size=14,col='text',weight='Regular',width){const n=track(figma.createText());n.name=value.slice(0,42);n.fontName={family:'Inter',style:weight};n.fontSize=size;n.lineHeight={unit:'PERCENT',value:140};n.characters=value;fill(n,col);if(styles['SmartLight/'+size+'/'+weight])n.textStyleId=styles['SmartLight/'+size+'/'+weight].id;if(width){n.textAutoResize='HEIGHT';n.resize(width,n.height);}else n.textAutoResize='WIDTH_AND_HEIGHT';if(parent)parent.appendChild(n);return n;}
function grow(n){n.layoutSizingHorizontal='FILL';return n;}
function labelPair(parent,left,right,w,size=14){const n=row(parent,'Label / value',w,8);grow(text(n,left,size));text(n,right,size,'muted');return n;}
function rect(parent,name,w,h,col,r=0){const n=track(figma.createRectangle());n.name=name;n.resize(w,h);fill(n,col);radius(n,r);parent.appendChild(n);return n;}
function circle(parent,w,col){const n=track(figma.createEllipse());n.name='Colour / '+col;n.resize(w,w);fill(n,col);parent.appendChild(n);return n;}
const paths={
 bulb:'<path d="M9 18h6m-5 3h4M8.7 14.5a6 6 0 1 1 6.6 0c-.8.5-1.3 1.2-1.3 2.5h-4c0-1.3-.5-2-1.3-2.5Z"/>',
 room:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10Z"/><path d="M9 21v-8h6v8"/>',
 scenes:'<path d="m12 2 2.7 7.3L22 12l-7.3 2.7L12 22l-2.7-7.3L2 12l7.3-2.7L12 2Z"/>',
 settings:'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3"/><circle cx="15" cy="17" r="3"/>',
 power:'<path d="M12 2v10M6 5a9 9 0 1 0 12 0"/>',
 sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5"/>',
 moon:'<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>',
 plus:'<path d="M12 5v14M5 12h14"/>',
 arrow:'<path d="m9 5 7 7-7 7"/>',
 back:'<path d="m15 5-7 7 7 7"/>',
 check:'<path d="m5 12 4 4L19 6"/>',
 wifi:'<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0m-11 4a6 6 0 0 1 8 0"/><circle cx="12" cy="20" r=".7"/>',
 more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 book:'<path d="M12 5v16M3 3c4-1 7 0 9 2 2-2 5-3 9-2v16c-4-1-7 0-9 2-2-2-5-3-9-2V3Z"/>',
 play:'<path d="m9 5 10 7-10 7V5Z"/>',
 strip:'<path d="M4 6h12a4 4 0 0 1 0 8H8a3 3 0 0 0 0 6h12M5 6v3m4-3v3m4-3v3m7 8v3m-4-3v3"/>',
 tube:'<rect x="3" y="8" width="18" height="8" rx="3"/><path d="M6 8v8m12-8v8"/>',
 transfer:'<path d="M3 7h17m-4-4 4 4-4 4M21 17H4m4-4-4 4 4 4"/>',
 shield:'<path d="m12 2 9 4v6c0 6-9 10-9 10S3 18 3 12V6l9-4Z"/><path d="m8 12 3 3 5-6"/>',
 edit:'<path d="m14 4 6 6M4 20l5-1L21 7a2 2 0 0 0-4-4L5 15l-1 5Z"/>',
 close:'<path d="m6 6 12 12M18 6 6 18"/>'
};
function icon(parent,name,col='text',size=22){const n=track(figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="'+(C[col]||col)+'" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">'+paths[name]+'</svg>'));n.name='Icon / '+name;n.resize(size,size);parent.appendChild(n);return n;}
function dotBadge(parent,value,col='mint'){const n=row(parent,value,110,7,0);n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='AUTO';circle(n,6,col);text(n,value,12,col,'Medium');return n;}
function outline(n){n.strokes=[paint('line')];n.strokeWeight=1;}
function setTextProperty(comp,node,name){const key=comp.addComponentProperty(name,'TEXT',node.characters);node.componentPropertyReferences={characters:key};return key;}
function component(n,name){const c=track(figma.createComponentFromNode(n));c.name=name;c.description='SmartLight '+name+'. Reusable native component for Android, Mac and Windows.';return c;}
function inst(parent,c,props,w){const n=track(c.createInstance());parent.appendChild(n);if(props){const mapped={};for(const [key,value]of Object.entries(props)){const property=Object.keys(n.componentProperties).find(p=>p.split('#')[0]===key);if(property)mapped[property]=value;}n.setProperties(mapped);}if(w)n.resize(w,n.height);return n;}
function slider(parent,w,percent=72,col='mint'){const rail=box(parent,'Brightness '+percent+'%',w,28,null);const b=rect(rail,'Track',w,6,'line',3);b.y=11;const f=rect(rail,'Fill',w*percent/100,6,col,3);f.y=11;const knob=circle(rail,20,col);knob.x=w*percent/100-10;knob.y=4;return rail;}
function gradient(a,b){return [{type:'GRADIENT_LINEAR',gradientTransform:[[1,0,0],[0,1,0]],gradientStops:[{position:0,color:{...rgb(a),a:1}},{position:1,color:{...rgb(b),a:1}}]}];}
function allIds(root){return [root.id,...root.findAll(()=>true).map(n=>n.id)];}
function evidence(root){const nodes=root.findAll(()=>true);return {id:root.id,name:root.name,width:root.width,height:root.height,counts:nodes.reduce((a,n)=>(a[n.type]=(a[n.type]||0)+1,a),{}),images:nodes.filter(n=>'fills'in n && Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE')).map(n=>n.id),fonts:[...new Set(nodes.filter(n=>n.type==='TEXT').map(n=>n.fontName.family))]};}
