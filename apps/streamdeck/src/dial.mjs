import {runAction,resolveSettings,validateSettings} from "./runner.mjs";
export function dialActions(settings){
 const items=settings?.actions;
 if(!Array.isArray(items)||items.length<1||items.length>32||new Set(items).size!==items.length||
   items.some(v=>typeof v!=="string"||!/^[a-zA-Z0-9_-]{1,64}$/.test(v)))throw new Error("Set up dial actions");
 return [...items];
}
export class DialController{
 constructor(run=runAction,delay=200){this.run=run;this.delay=delay;this.entries=new Map();this.busy=new Set();this.global={};}
 async ready(dial,settings){
  clearTimeout(this.entries.get(dial.id)?.timer);
  const entry={dial,settings:{...settings},index:0,actions:[],valid:false,level:50,pending:false,paused:false,timer:null};
  try{entry.actions=dialActions(settings.brightnessMode?{actions:[settings.action]}:settings);validateSettings({...resolveSettings(settings,this.global),action:entry.actions[0]});entry.valid=true;}catch{}
  this.entries.set(dial.id,entry);
  await dial.setFeedback({title:entry.valid?"Turn to choose":"Set up",value:entry.valid?this.label(entry):"Add actions",icon:"imgs/light.svg"});
 }
 disappear(dial){clearTimeout(this.entries.get(dial.id)?.timer);this.entries.delete(dial.id);}
 continuous(entry){return entry.settings.brightnessMode===true && entry.settings.continuous===true;}
 schedule(entry){
  if(entry.timer||!entry.pending||entry.paused||this.entries.get(entry.dial.id)!==entry)return;
  entry.timer=setTimeout(()=>{entry.timer=null;void this.press(entry.dial,false);},this.delay);
 }
 async update(global){this.global=global||{};await Promise.all([...this.entries.values()].filter(e=>e.settings.useShared===true).map(e=>this.ready(e.dial,e.settings)));}
 label(entry){return entry.settings.brightnessMode?`${entry.level}%`:entry.actions[entry.index];}
 async rotate(dial,ticks){
  const entry=this.entries.get(dial.id);
  if(!entry?.valid||(!this.continuous(entry)&&this.busy.has(dial.id))||!Number.isSafeInteger(ticks)||ticks===0)return;
  const before=entry.level;
  if(entry.settings.brightnessMode)entry.level=Math.max(1,Math.min(100,entry.level+Math.max(-100,Math.min(100,ticks))*5));
  else{const length=entry.actions.length;entry.index=((entry.index+ticks%length)%length+length)%length;}
  if(this.continuous(entry)){
   if(entry.level===before)return;
   entry.pending=!entry.paused;
   await dial.setFeedback({title:entry.paused?"Paused; press to send":"Preview",value:this.label(entry)});
   if(!this.busy.has(dial.id))this.schedule(entry);
  }else await dial.setFeedback({title:"Press to run",value:this.label(entry)});
 }
 async press(dial,manual=true){
  const entry=this.entries.get(dial.id);
  if(!entry?.valid){await dial.showAlert();return;}
  if(this.busy.has(dial.id))return;
  if(!manual && (!entry.pending || entry.paused))return;
  clearTimeout(entry.timer);entry.timer=null;entry.pending=false;
  if(manual)entry.paused=false;
  this.busy.add(dial.id);
  const action=entry.actions[entry.index];
  const settings={...resolveSettings(entry.settings,this.global),action};
  if(entry.settings.brightnessMode)settings.brightness=entry.level;
  const label=this.label(entry);
  const visible=()=>this.entries.get(dial.id)===entry;
  try{
   await dial.setFeedback({title:"Sending...",value:label});
   const result=await this.run(settings);
   if(entry.settings.brightnessMode && entry.level===settings.brightness)entry.pending=false;
   if(visible()&&!entry.pending)await dial.setFeedback({title:result.confirmation==="simulated"?"Simulated":"Sent",value:label});
  }catch{
   entry.pending=false;entry.paused=true;clearTimeout(entry.timer);
   if(visible()){await dial.setFeedback({title:this.continuous(entry)?"Paused; check hub":"Failed; check hub",value:label});await dial.showAlert();}
  }finally{
   this.busy.delete(dial.id);
   if(visible()&&this.continuous(entry))this.schedule(entry);
  }
 }
}
