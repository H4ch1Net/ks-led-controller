import {KeyController,validateSettings,runJson,checkDelivery} from "./runner.mjs";
import {StatePool} from "./state.mjs";

const names={power:"Power",color:"Color",effect:"Effect",brightness:"Brightness",scene:"Scene"};
const id=value=>typeof value==="string"&&/^[a-zA-Z0-9_-]{1,64}$/.test(value);
const integer=(value,min,max)=>Number.isInteger(value)&&value>=min&&value<=max;
export function requestFor(s) {
  const type=s.kind;
  if(!names[type]||!id(type==="scene"?s.scene:s.light))throw new Error("Choose a target");
  if(type==="scene")return {type,scene:s.scene};
  const request={type,light:s.light};
  if(type==="power") {
    if(!["on","off","toggle"].includes(s.power))throw new Error("Choose power behavior");
    return {...request,power:s.power};
  }
  if(!integer(s.level,1,100))throw new Error("Invalid brightness");
  request.brightness=s.level;
  if(type==="color") {
    if(typeof s.color!=="string"||!/^#[0-9a-f]{6}$/i.test(s.color))throw new Error("Choose a color");
    const response=s.colorResponse??"raw";
    const gamma={raw:1,balanced:2.2,vivid:2.5}[response];
    if(gamma===undefined)throw new Error("Choose color response");
    request.rgb=s.color.slice(1).match(/../g).map(v=>Math.round(255*Math.pow(parseInt(v,16)/255,gamma)));
  }
  if(type==="effect") {
    if(!integer(s.effect,130,138)||!integer(s.speed,0,100))throw new Error("Choose an effect");
    request.effect=s.effect;request.speed=s.speed;
  }
  return request;
}
export function connectionSettings(connection) {
  return validateSettings({...connection,action:"Setup"});
}
export async function catalog(connection) {
  const s=connectionSettings(connection);
  const result=await runJson(s,["-m","ks_light.streamdeck","--config",s.config],{timeoutMs:15000});
  if(!Array.isArray(result.lights)||!Array.isArray(result.scenes))throw new Error("Invalid catalog");
  return result;
}
export function directRun(s) {
  connectionSettings(s);
  return runJson(s,["-m","ks_light.streamdeck","--config",s.config,"--request",JSON.stringify(requestFor(s))]).then(checkDelivery);
}
export class DirectController {
  constructor() {
    this.global={};this.keys=new Map();this.pool=new StatePool();
    this.controller=new KeyController(directRun,{subscribe:(s,callback)=>this.pool.subscribe(s,state=>{
      let label=state.lights?.[s.light];
      if(s.kind==="power"&&typeof state.powers?.[s.light]==="boolean") {
        const provenance=/^(Sim|Saved|Sent)\b/.exec(label||"")?.[1];
        if(provenance)label=`${provenance} ${state.powers[s.light]?"On":"Off"}`;
      }
      return callback({...state,states:{[s.action]:typeof label==="string"?label:"Unknown"}});
    })});
  }
  settings(local) {
    const title=local.kind==="power"&&["on","off"].includes(local.power)?(local.power==="on"?"On":"Off"):names[local.kind];
    const s={...local,...this.global.connection,action:title||"Set up",showState:local.kind!=="scene"};
    requestFor(s);return s;
  }
  async ready(key,local) {
    this.keys.set(key.id,{key,local:{...local}});
    let s;
    try{s=this.settings(local);}catch{s={action:"Set up"};}
    if(local.kind==="power")s.onState=state=>key.setState(state.status==="online"&&state.powers?.[local.light]===true?1:0);
    await this.controller.ready(key,s);
    if(local.kind==="color"&&/^#[0-9a-f]{6}$/i.test(local.color||"")) {
      const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144"><rect width="144" height="144" rx="24" fill="#1e2232"/><circle cx="72" cy="40" r="23" fill="${local.color}" stroke="#ffffff" stroke-width="3"/></svg>`;
      await key.setImage(`data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`);
    }
  }
  async press(key,local) {
    try {await this.controller.press(key,this.settings(local));}
    catch {await key.setTitle("Set up");await key.showAlert();}
  }
  disappear(key){this.keys.delete(key.id);this.controller.disappear(key);}
  async update(global){this.global=global||{};await Promise.all([...this.keys.values()].map(({key,local})=>this.ready(key,local)));}
}
