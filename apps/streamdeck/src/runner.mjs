import {spawn} from "node:child_process";
import path from "node:path";
import {StatePool} from "./state.mjs";

function keyStatusLabel(label) {
  // Keep provenance visible on 72px keys; full RGB/effect IDs belong in the hub.
  const detail=/^(Sim|Saved|Sent) (#[0-9A-F]{6}|Effect \d+)(?: (\d+%))?$/.exec(label);
  if (!detail) return label === "Hub offline" ? "Hub\noffline" : label;
  return `${detail[1]}\n${detail[2].startsWith("#") ? "Color" : "FX"}${detail[3] ? ` ${detail[3]}` : ""}`;
}

export function validateSettings(s) {
  if (!s || !["python", "repository", "config"].every(k => typeof s[k] === "string" && path.isAbsolute(s[k]) && !/[\r\n\0]/.test(s[k])) ||
      typeof s.action !== "string" || !/^[a-zA-Z0-9_-]{1,64}$/.test(s.action)) throw new Error("Configure this key first");
  return s;
}
export function runAction(settings, {spawnProcess=spawn, timeoutMs=125000}={}) {
  const s=validateSettings(settings);
  if(s.brightness!==undefined && (!Number.isInteger(s.brightness)||s.brightness<1||s.brightness>100))throw new Error("Invalid brightness");
  const args=["-m","ks_light.controller","--config",s.config,s.action];
  if(s.brightness!==undefined)args.push("--brightness",String(s.brightness));
  return runJson(s,args,{spawnProcess,timeoutMs}).then(checkDelivery);
}
export function checkDelivery(result) {
  if(result.status!=="succeeded" || !["simulated","unconfirmed"].includes(result.confirmation)) throw new Error("Invalid response");
  return result;
}
export function runJson(s,args,{spawnProcess=spawn,timeoutMs=125000}={}) {
  return new Promise((resolve,reject)=>{
    let done=false, output="", size=0;
    const child=spawnProcess(s.python,args,
      {cwd:s.repository,windowsHide:true,shell:false,stdio:["ignore","pipe","pipe"]});
    const finish=(error,result)=>{if(done)return;done=true;clearTimeout(timer);error?reject(error):resolve(result);};
    const timer=setTimeout(()=>{child.kill();finish(new Error("Timed out; check light"));},timeoutMs);
    child.stdout.on("data",data=>{
      size+=data.length;
      if(size>65536){child.kill();finish(new Error("Invalid response"));return;}
      output+=data.toString();
    });
    // Drain stderr but never send private paths, server messages or credentials to Stream Deck.
    child.stderr.on("data",()=>{});
    child.on("error",()=>finish(new Error("Could not start client")));
    child.on("close",code=>{
      if(done)return;
      if(code!==0){finish(new Error(code===1?"Delivery failed":"Check setup or hub"));return;}
      try {
        const result=JSON.parse(output);
        finish(null,result);
      } catch {finish(new Error("Invalid response"));}
    });
  });
}

export class KeyController {
  constructor(run=runAction,statePool=new StatePool()){this.run=run;this.statePool=statePool;this.watchers=new Map();this.busy=new Set();this.versions=new Map();this.sequence=0;}
  async ready(key,settings){
    this.watchers.get(key.id)?.();this.watchers.delete(key.id);
    const version=++this.sequence;this.versions.set(key.id,version);
    let title=settings?.action || "Set up";
    let valid=true;
    try {validateSettings(settings);} catch {title="Set up";valid=false;}
    await key.setTitle(title);
    if(valid&&settings.showState===true&&this.versions.get(key.id)===version){
      this.watchers.set(key.id,this.statePool.subscribe(settings,async state=>{
        if(this.versions.get(key.id)!==version||this.busy.has(key.id))return;
        if(settings.onState)await settings.onState(state);
        if(this.versions.get(key.id)!==version||this.busy.has(key.id))return;
        const label=state.status==="online"?state.states[settings.action]||"Unavailable":"Hub offline";
        await key.setTitle(`${settings.action}\n${keyStatusLabel(label)}`);
      }));
    }
  }
  disappear(key){this.versions.delete(key.id);this.watchers.get(key.id)?.();this.watchers.delete(key.id);}
  async press(key,settings){
    if(this.busy.has(key.id))return;
    this.busy.add(key.id);
    const version=this.versions.get(key.id);
    const visible=()=>this.versions.has(key.id)&&this.versions.get(key.id)===version;
    try {
      await key.setTitle("Sending...");
      const result=await this.run(settings);
      if(visible()){
        await key.setTitle(`${settings.action}\n${result.confirmation==="simulated"?"Simulated":"Sent"}`);
        await key.showOk();
      }
    } catch {
      if(visible()){await key.setTitle(`${settings?.action || "KS Light"}\nFailed`);await key.showAlert();}
    } finally {this.busy.delete(key.id);}
  }
}

// Explicit opt-in: legacy keys never inherit a different connection implicitly.
export function resolveSettings(local, global) {
  if (local?.useShared !== true) return {...local};
  const connection=global?.connection || {};
  return {action:local.action,showState:local.showState,python:connection.python,repository:connection.repository,config:connection.config};
}

export class SharedController {
  constructor(controller=new KeyController()){this.controller=controller;this.global={};this.keys=new Map();}
  async ready(key,settings){
    this.keys.set(key.id,{key,settings:{...settings}});
    await this.controller.ready(key,resolveSettings(settings,this.global));
  }
  disappear(key){this.keys.delete(key.id);this.controller.disappear(key);}
  async update(global){
    this.global=global || {};
    await Promise.all([...this.keys.values()].filter(v=>v.settings.useShared===true)
      .map(v=>this.controller.ready(v.key,resolveSettings(v.settings,this.global))));
  }
  async press(key,settings){await this.controller.press(key,resolveSettings(settings,this.global));}
}
