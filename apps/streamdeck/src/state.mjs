import {spawn} from "node:child_process";

// One read-only process per connection, shared by all visible opted-in keys.
export class StatePool {
  constructor(spawnProcess=spawn){this.spawn=spawnProcess;this.entries=new Map();}
  subscribe(settings, listener){
    const id=JSON.stringify([settings.python,settings.repository,settings.config]);
    let entry=this.entries.get(id);
    if(!entry){entry={settings,listeners:new Set(),child:null,timer:null,latest:{status:"offline"}};this.entries.set(id,entry);}
    entry.listeners.add(listener);
    this.notify(listener,entry.latest);
    if(!entry.child&&!entry.timer)this.start(entry);
    return ()=>{
      entry.listeners.delete(listener);
      if(!entry.listeners.size){this.entries.delete(id);clearTimeout(entry.timer);clearTimeout(entry.watchdog);const child=entry.child;entry.child=null;child?.kill();}
    };
  }
  notify(listener,value){try{Promise.resolve(listener(value)).catch(()=>{});}catch{}}
  publish(entry,value){entry.latest=value;for(const listener of entry.listeners)this.notify(listener,value);}
  start(entry){
    let child, buffer="";
    const failed=()=>{
      if(entry.child!==child)return;
      clearTimeout(entry.watchdog);
      entry.child=null;child?.kill();this.publish(entry,{status:"offline"});
      if(entry.listeners.size)entry.timer=setTimeout(()=>{entry.timer=null;this.start(entry);},30000);
    };
    try{
      child=this.spawn(entry.settings.python,["-m","ks_light.controller_status","--config",entry.settings.config],
        {cwd:entry.settings.repository,windowsHide:true,shell:false,stdio:["ignore","pipe","pipe"]});
      entry.child=child;
      entry.watchdog=setTimeout(failed,60000);
      child.stdout.on("data",data=>{
        if(entry.child!==child)return;
        buffer+=data.toString();
        if(buffer.length>65536){failed();return;}
        let index;
        while((index=buffer.indexOf("\n"))>=0){
          const line=buffer.slice(0,index);buffer=buffer.slice(index+1);
          try{
            const value=JSON.parse(line);
            if(!["online","offline"].includes(value.status)||value.status==="online"&&
              (!value.states||Array.isArray(value.states)||typeof value.states!=="object"||
               Object.entries(value.states).some(([k,v])=>!/^[a-zA-Z0-9_-]{1,64}$/.test(k)||typeof v!=="string"||v.length>64||/[\r\n\0]/.test(v))))throw new Error();
            if(value.lights!==undefined&&(!value.lights||Array.isArray(value.lights)||typeof value.lights!=="object"||
              Object.entries(value.lights).some(([k,v])=>!/^[a-zA-Z0-9_-]{1,64}$/.test(k)||typeof v!=="string"||v.length>64||/[\r\n\0]/.test(v))))throw new Error();
            clearTimeout(entry.watchdog);entry.watchdog=setTimeout(failed,60000);
            this.publish(entry,value);
          }catch{failed();return;}
        }
      });
      child.stderr.on("data",()=>{});
      child.on("error",failed);child.on("close",failed);
    }catch{entry.child=child;failed();}
  }
}
