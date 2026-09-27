import {test} from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import {readFileSync} from "node:fs";
const source=readFileSync(new URL("../dev.kslight.controller.sdPlugin/ui/settings.js",import.meta.url),"utf8");
function inspector(settings={},action="dev.kslight.controller.run"){
 const nodes=Object.fromEntries(["python","repository","config","action","shared","scope","status","save","saveConnection"].map(id=>[id,{value:"",checked:false}]));
 if(action==="dev.kslight.controller.brightness")nodes.continuous={checked:false};
 if(action==="dev.kslight.controller.run")nodes.showState={checked:false};
 let socket;class Socket{static OPEN=1;readyState=1;sent=[];constructor(){socket=this;}send(raw){this.sent.push(JSON.parse(raw));}}
 const context={window:{},document:{getElementById:id=>nodes[id]},WebSocket:Socket};vm.runInNewContext(source,context);
 context.window.connectElgatoStreamDeckSocket(1,"inspector","registerPropertyInspector","{}",JSON.stringify({action,payload:{settings}}));socket.onopen();
 return {nodes,socket,receive:settings=>socket.onmessage({data:JSON.stringify({event:"didReceiveGlobalSettings",payload:{settings}})})};
}
const paths={python:"C:\\KS\\python.exe",repository:"C:\\KS",config:"C:\\KS\\controller.json"};
test("live state display remains explicit and saves its opt-in",()=>{
 const ui=inspector({...paths,action:"on"});assert.equal(ui.nodes.showState.checked,false);
 ui.nodes.showState.checked=true;ui.nodes.save.onclick();assert.equal(ui.socket.sent.at(-1).payload.showState,true);
});
test("continuous dimming setting is explicit and persists only on brightness action",()=>{
 const ui=inspector({...paths,action:"reading"},"dev.kslight.controller.brightness");
 assert.equal(ui.nodes.continuous.checked,false);ui.nodes.continuous.checked=true;ui.nodes.save.onclick();
 assert.equal(ui.socket.sent.at(-1).payload.continuous,true);
});
test("existing key remains local and global update preserves unsaved edits",()=>{
 const ui=inspector({...paths,action:"on"});assert.equal(ui.nodes.shared.checked,false);
 ui.nodes.config.value="D:\\draft.json";ui.receive({connection:paths});assert.equal(ui.nodes.config.value,"D:\\draft.json");
 ui.nodes.save.onclick();const saved=ui.socket.sent.at(-1);assert.equal(saved.event,"setSettings");assert.equal(saved.payload.useShared,false);
 assert.equal(saved.payload.config,"D:\\draft.json");
});
test("shared setup must load and save separately; action remains per key",()=>{
 const ui=inspector({...paths,action:"on"});ui.nodes.shared.checked=true;ui.nodes.shared.onchange();
 ui.nodes.saveConnection.onclick();assert.match(ui.nodes.status.textContent,/Waiting/);
 ui.receive({connection:paths,other:"preserved"});ui.nodes.config.value="D:\\shared.json";
 ui.nodes.save.onclick();assert.match(ui.nodes.status.textContent,/Save shared/);
 ui.nodes.saveConnection.onclick();assert.equal(ui.socket.sent.at(-1).event,"setGlobalSettings");assert.equal(ui.socket.sent.at(-1).payload.other,"preserved");
 ui.nodes.save.onclick();assert.equal(ui.socket.sent.at(-1).payload.useShared,true);assert.equal(ui.socket.sent.at(-1).payload.config,paths.config);
 ui.nodes.shared.checked=false;ui.nodes.shared.onchange();assert.equal(ui.nodes.config.value,paths.config);
});
test("relative paths and disconnected saves are rejected",()=>{
 const ui=inspector({...paths,action:"on"});ui.nodes.config.value="relative.json";const before=ui.socket.sent.length;
 ui.nodes.save.onclick();assert.equal(ui.socket.sent.length,before);
 ui.nodes.config.value=paths.config;ui.socket.readyState=3;ui.nodes.save.onclick();assert.match(ui.nodes.status.textContent,/disconnected/);
});

test("dial inspector saves ordered action list and rejects duplicates",()=>{
 const ui=inspector({...paths,actions:["on","off"]},"dev.kslight.controller.dial");
 assert.equal(ui.nodes.action.value,"on, off");ui.nodes.action.value="on, reading, off";ui.nodes.save.onclick();
 assert.deepEqual(ui.socket.sent.at(-1).payload.actions,["on","reading","off"]);assert.equal(ui.socket.sent.at(-1).payload.action,undefined);
 const count=ui.socket.sent.length;ui.nodes.action.value="on, on";ui.nodes.save.onclick();assert.equal(ui.socket.sent.length,count);
});
