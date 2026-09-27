import {test} from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import {DialController,dialActions} from "../src/dial.mjs";
const settings={python:path.resolve("python"),repository:path.resolve("repo"),config:path.resolve("config"),actions:["on","reading","off"]};
const pause=()=>new Promise(resolve=>setTimeout(resolve,30));
function dial(){return {id:"dial",feedback:[],alerts:0,async setFeedback(v){this.feedback.push(v);},async showAlert(){this.alerts++;}};}
test("continuous dimming coalesces rapid turns and serializes latest level",async()=>{
 const calls=[];let finish;
 const c=new DialController(s=>{calls.push(s.brightness);return new Promise(resolve=>finish=resolve);},5),ui=dial();
 await c.ready(ui,{...settings,brightnessMode:true,continuous:true,action:"reading"});
 await c.rotate(ui,1);await c.rotate(ui,2);await pause();assert.deepEqual(calls,[65]);
 await c.rotate(ui,1);await c.rotate(ui,2);await pause();assert.deepEqual(calls,[65]);
 finish({confirmation:"simulated"});await pause();assert.deepEqual(calls,[65,80]);
 finish({confirmation:"simulated"});await pause();assert.equal(ui.feedback.at(-1).value,"80%");
 c.disappear(ui);
});
test("uncertain failure drops pending dimming and pauses until a deliberate press",async()=>{
 let fail,calls=0;
 const c=new DialController(()=>{calls++;return new Promise((_,reject)=>fail=reject);},5),ui=dial();
 await c.ready(ui,{...settings,brightnessMode:true,continuous:true,action:"reading"});
 await c.rotate(ui,1);await pause();await c.rotate(ui,2);fail(Error("uncertain"));await pause();
 assert.equal(calls,1);assert.match(ui.feedback.at(-1).title,/Paused/);
 await c.rotate(ui,1);await pause();assert.equal(calls,1);
 c.run=async s=>{calls++;assert.equal(s.brightness,70);return {confirmation:"unconfirmed"};};
 await c.press(ui);assert.equal(calls,2);await pause();assert.equal(calls,2);c.disappear(ui);
});
test("disappearance and settings changes cancel scheduled continuous sends",async()=>{
 let calls=0;const c=new DialController(async()=>{calls++;return {confirmation:"unconfirmed"};},5),ui=dial();
 const config={...settings,brightnessMode:true,continuous:true,action:"reading"};
 await c.ready(ui,config);await c.rotate(ui,1);c.disappear(ui);await pause();assert.equal(calls,0);
 await c.ready(ui,config);await c.rotate(ui,1);await c.ready(ui,{...config,action:"other"});await pause();assert.equal(calls,0);
 c.disappear(ui);
});
test("rotation previews wrap in both directions and never sends",async()=>{
 let calls=0;const c=new DialController(async()=>{calls++;return {confirmation:"simulated"};}),ui=dial();
 await c.ready(ui,settings);await c.rotate(ui,-1);assert.equal(ui.feedback.at(-1).value,"off");
 await c.rotate(ui,4);assert.equal(ui.feedback.at(-1).value,"on");
 await c.rotate(ui,1.5);assert.equal(ui.feedback.at(-1).value,"on");assert.equal(calls,0);
 await c.press(ui);assert.equal(calls,1);assert.equal(ui.feedback.at(-1).title,"Simulated");
});
test("invalid lists and missing shared connection cannot run",async()=>{
 for(const actions of [[],["bad name"],["on","on"],Array(33).fill("on"),null])assert.throws(()=>dialActions({actions}));
 let calls=0;const c=new DialController(async()=>calls++),ui=dial();
 await c.ready(ui,{...settings,useShared:true});await c.press(ui);assert.equal(calls,0);assert.equal(ui.alerts,1);
});
test("busy rotations and repeated presses are discarded; changed setup suppresses old result",async()=>{
 let finish,calls=0;const c=new DialController(()=>{calls++;return new Promise(r=>finish=r);}),ui=dial();
 await c.update({connection:settings});await c.ready(ui,{useShared:true,actions:settings.actions});
 const pending=c.press(ui);await Promise.resolve();await c.rotate(ui,1);await c.press(ui);
 assert.equal(calls,1);assert.equal(ui.feedback.at(-1).value,"on");
 await c.update({connection:{...settings,config:path.resolve("new")}});
 finish({confirmation:"unconfirmed"});await pending;assert.equal(ui.feedback.at(-1).title,"Turn to choose");
});
test("disappearance suppresses feedback and failure releases busy gate",async()=>{
 let finish;const c=new DialController(()=>new Promise(r=>finish=r)),ui=dial();
 await c.ready(ui,settings);const pending=c.press(ui);await Promise.resolve();c.disappear(ui);
 finish({confirmation:"unconfirmed"});await pending;assert.equal(ui.feedback.at(-1).title,"Sending...");
 let calls=0;c.run=async()=>{calls++;throw Error("private");};await c.ready(ui,settings);
 await c.press(ui);await c.press(ui);assert.equal(calls,2);assert.equal(ui.alerts,2);assert.equal(ui.feedback.at(-1).title,"Failed; check hub");
});

test("brightness previews clamp without sending and press snapshots the explicit percentage",async()=>{
 const calls=[];const c=new DialController(async s=>{calls.push(s);return {confirmation:"unconfirmed"};}),ui=dial();
 await c.ready(ui,{...settings,brightnessMode:true,action:"reading"});assert.equal(ui.feedback.at(-1).value,"50%");
 await c.rotate(ui,1);assert.equal(ui.feedback.at(-1).value,"55%");assert.equal(calls.length,0);
 await c.press(ui);assert.equal(calls[0].brightness,55);assert.equal(calls[0].action,"reading");
 await c.rotate(ui,-10000);assert.equal(ui.feedback.at(-1).value,"1%");
 await c.rotate(ui,10000);assert.equal(ui.feedback.at(-1).value,"100%");
});
