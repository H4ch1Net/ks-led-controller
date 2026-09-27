import {test} from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import {EventEmitter} from "node:events";
import {PassThrough} from "node:stream";
import {runAction,validateSettings,KeyController,SharedController,resolveSettings} from "../src/runner.mjs";
const settings={python:path.resolve("space folder/python.exe"),repository:path.resolve("repository"),config:path.resolve("settings file.json"),action:"desk-on"};
function fakeProcess(){const c=new EventEmitter();c.stdout=new PassThrough();c.stderr=new PassThrough();c.kill=()=>{c.killed=true;};return c;}
function key(){return {id:"one",titles:[],ok:0,alerts:0,async setTitle(v){this.titles.push(v);},async showOk(){this.ok++;},async showAlert(){this.alerts++;}};}
test("argument array protects spaces and uses no shell",async()=>{
 const child=fakeProcess();let captured;
 const result=runAction(settings,{spawnProcess:(...args)=>{captured=args;return child;}});
 child.stdout.write(JSON.stringify({status:"succeeded",confirmation:"simulated"}));child.emit("close",0);
 assert.equal((await result).confirmation,"simulated");
 assert.equal(captured[0],settings.python);assert.deepEqual(captured[1],["-m","ks_light.controller","--config",settings.config,"desk-on"]);
 assert.equal(captured[2].shell,false);assert.equal(captured[2].windowsHide,true);
});
test("failed exit is not successful and private stderr is omitted",async()=>{
 const child=fakeProcess();const result=runAction(settings,{spawnProcess:()=>child});
 child.stderr.write("secret private path");child.emit("close",1);
 await assert.rejects(result,{message:"Delivery failed"});
});
test("invalid output cannot show success",async()=>{
 const child=fakeProcess();const result=runAction(settings,{spawnProcess:()=>child});
 child.stdout.write('{"status":"pending"}');child.emit("close",0);await assert.rejects(result,/Invalid response/);
});
test("deadline terminates client and never restarts it",async()=>{
 const child=fakeProcess();let calls=0;
 const result=runAction(settings,{timeoutMs:5,spawnProcess:()=>{calls++;return child;}});
 await assert.rejects(result,/Timed out/);assert.equal(child.killed,true);assert.equal(calls,1);
});
test("rejects missing paths and invalid action before spawn",()=>{
 assert.throws(()=>validateSettings({...settings,config:"relative.json"}));
 assert.throws(()=>validateSettings({...settings,action:"on & arbitrary"}));
});
test("duplicate press ignored until completion, simulator feedback explicit",async()=>{
 let finish,calls=0;const ui=key();const controller=new KeyController(()=>{calls++;return new Promise(r=>finish=r);});
 await controller.ready(ui,settings);const pending=controller.press(ui,settings);
 await Promise.resolve();await controller.press(ui,settings);assert.equal(calls,1);assert.equal(ui.titles.at(-1),"Sending...");
 finish({confirmation:"simulated"});await pending;
 assert.equal(ui.titles.at(-1),"desk-on\nSimulated");assert.equal(ui.ok,1);
});
test("disappeared and reappeared key cannot receive stale completion",async()=>{
 let finish;const ui=key();const controller=new KeyController(()=>new Promise(r=>finish=r));
 await controller.ready(ui,settings);const pending=controller.press(ui,settings);await Promise.resolve();
 controller.disappear(ui);await controller.ready(ui,{...settings,action:"desk-off"});
 finish({confirmation:"unconfirmed"});await pending;assert.equal(ui.titles.at(-1),"desk-off");assert.equal(ui.ok,0);
});
test("failed command alerts key and releases busy gate",async()=>{
 const ui=key();let calls=0;const controller=new KeyController(async()=>{calls++;throw new Error("private");});
 await controller.ready(ui,settings);await controller.press(ui,settings);await controller.press(ui,settings);
 assert.equal(calls,2);assert.equal(ui.alerts,2);assert.equal(ui.ok,0);assert.equal(ui.titles.at(-1),"desk-on\nFailed");
});

test("shared setup is opt-in and never mixes local and shared paths",()=>{
 const global={connection:{...settings,config:path.resolve("shared.json")}};
 assert.equal(resolveSettings(settings,global).config,settings.config);
 assert.equal(resolveSettings({...settings,useShared:true},global).config,global.connection.config);
 assert.equal(resolveSettings({...settings,useShared:true},{}).config,undefined);
 assert.throws(()=>validateSettings(resolveSettings({...settings,useShared:true},{})));
 assert.equal(resolveSettings({...settings,useShared:false},global).config,settings.config);
});
test("shared edits refresh opted-in keys only and invalidate old completion",async()=>{
 let finish;const first=key(),second=key();second.id="two";
 const base=new KeyController(()=>new Promise(r=>finish=r));const shared=new SharedController(base);
 await shared.update({connection:settings});
 await shared.ready(first,{action:"desk-on",useShared:true});await shared.ready(second,settings);
 const pending=shared.press(first,{action:"desk-on",useShared:true});await Promise.resolve();
 const before=second.titles.length;
 await shared.update({connection:{...settings,config:path.resolve("replacement.json")}});
 finish({confirmation:"unconfirmed"});await pending;
 assert.equal(first.ok,0);assert.equal(first.titles.at(-1),"desk-on");assert.equal(second.titles.length,before);
 shared.disappear(first);await shared.update({});assert.equal(first.titles.at(-1),"desk-on");
});
test("each new press snapshots shared paths while retaining the per-key action",async()=>{
 const calls=[];const shared=new SharedController(new KeyController(async s=>{calls.push(s);return {confirmation:"simulated"};}));
 const ui=key(),local={useShared:true,action:"desk-off"};
 await shared.update({connection:settings});await shared.ready(ui,local);await shared.press(ui,local);
 await shared.update({connection:{...settings,config:path.resolve("other.json")}});await shared.press(ui,local);
 assert.equal(calls[0].action,"desk-off");assert.equal(calls[0].config,settings.config);
 assert.notEqual(calls[0].config,calls[1].config);
});

test("brightness is a validated argument and never changes the configured action name",async()=>{
 const child=fakeProcess();let args;const result=runAction({...settings,brightness:55},{spawnProcess:(exe,a)=>{args=a;return child;}});
 child.stdout.write(JSON.stringify({status:"succeeded",confirmation:"unconfirmed"}));child.emit("close",0);await result;
 assert.deepEqual(args.slice(-3),["desk-on","--brightness","55"]);
 for(const brightness of [0,101,NaN,"50",true])assert.throws(()=>runAction({...settings,brightness}));
});
