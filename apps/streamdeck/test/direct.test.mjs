import {test} from "node:test";
import assert from "node:assert/strict";
import {requestFor} from "../src/direct.mjs";
const color={kind:"color",light:"desk",color:"#ff7800",level:50};
test("color response preserves old settings and primary endpoints, compensates the user's warm-orange example",()=>{
 assert.deepEqual(requestFor(color).rgb,[255,120,0]);
 assert.deepEqual(requestFor({...color,colorResponse:"vivid"}).rgb,[255,39,0]);
 for(const response of ["raw","balanced","vivid"]){
  assert.deepEqual(requestFor({...color,color:"#0000ff",colorResponse:response}).rgb,[0,0,255]);
  assert.equal(requestFor({...color,colorResponse:response}).brightness,50);
 }
 assert.throws(()=>requestFor({...color,colorResponse:"unexpected"}));
});
