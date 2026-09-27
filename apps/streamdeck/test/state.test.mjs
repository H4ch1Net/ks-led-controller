import {test} from "node:test";
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import {PassThrough} from "node:stream";
import path from "node:path";
import {StatePool} from "../src/state.mjs";
import {KeyController} from "../src/runner.mjs";
const settings={python:path.resolve("python.exe"),repository:path.resolve("repo"),config:path.resolve("controller.json"),action:"on",showState:true};
function child(){const c=new EventEmitter();c.stdout=new PassThrough();c.stderr=new PassThrough();c.kill=()=>{c.killed=true;};return c;}

test("visible keys share a single read-only process and release it after the last disappears",()=>{
  let count=0,args;const process=child();const pool=new StatePool((...v)=>{count++;args=v;return process;});
  const first=[],second=[];
  const stop1=pool.subscribe(settings,value=>first.push(value));
  const stop2=pool.subscribe({...settings,action:"off"},value=>second.push(value));
  assert.equal(count,1);assert.equal(args[1][1],"ks_light.controller_status");assert.equal(args[2].shell,false);
  process.stdout.write('{"status":"online","states":{"on":"Sent On"}}\n');
  assert.equal(first.at(-1).states.on,"Sent On");assert.equal(second.at(-1).states.on,"Sent On");
  stop1();assert.equal(process.killed,undefined);stop2();assert.equal(process.killed,true);
  const length=first.length;process.stdout.write('{"status":"offline"}\n');assert.equal(first.length,length);
});

test("invalid status stops the reader without echoing process output",()=>{
  const process=child(),values=[];const pool=new StatePool(()=>process);
  const stop=pool.subscribe(settings,value=>values.push(value));
  process.stderr.write("private token");process.stdout.write('{"status":"online","states":{"on":"private\\ntext"}}\n');
  assert.deepEqual(values.at(-1),{status:"offline"});assert.equal(process.killed,true);stop();
});

test("status cannot overwrite an in-flight command or a reconfigured key",async()=>{
  let listener,finish,stops=0;
  const pool={subscribe(s,callback){listener=callback;return ()=>stops++;}};
  const controller=new KeyController(()=>new Promise(resolve=>finish=resolve),pool);
  const key={id:"one",titles:[],async setTitle(title){this.titles.push(title);},async showOk(){},async showAlert(){}};
  await controller.ready(key,settings);
  await listener({status:"online",states:{on:"Sent Off"}});assert.equal(key.titles.at(-1),"on\nSent Off");
  const pending=controller.press(key,settings);await Promise.resolve();
  await listener({status:"offline"});assert.equal(key.titles.at(-1),"Sending...");
  const old=listener;await controller.ready(key,{...settings,showState:false,action:"off"});
  await old({status:"online",states:{on:"Sent On"}});finish({confirmation:"unconfirmed"});await pending;
  assert.equal(key.titles.at(-1),"off");assert.equal(stops,1);
});
