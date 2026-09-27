let socket,context,actionUUID,kind,local={},global={},loaded=false,requestId="",choices=[];
const $=id=>document.getElementById(id);
const labels={power:"Power",color:"Set Color",effect:"Effect",level:"Brightness",scene:"Scene"};
function send(event,payload){if(socket?.readyState!==WebSocket.OPEN)return false;socket.send(JSON.stringify({event,context,...(event==="sendToPlugin"?{action:actionUUID}:{}),...(payload===undefined?{}:{payload})}));return true;}
function refresh(){requestId=String(Date.now())+Math.random();$("status").textContent="Connecting to hub…";send("sendToPlugin",{event:"catalog",requestId});}
function updateLabels(){
 $("levelValue").textContent=$("level").value+"%";$("speedValue").textContent=$("speed").value+"%";
 $("effectColorSection").hidden=$("animation").value!=="breathing";
}
function save(){
 updateLabels();
 if(!$("target").value){$("status").textContent="Choose a target first.";return;}
 const s={...local};
 if(kind==="color") {
  const target=choices.find(item=>item.id===$("target").value);
  if(target&&!target.capabilities?.brightness)$("level").value="100";
  $("levelSection").hidden=!!target&&!target.capabilities?.brightness;
 }
 if(kind==="scene")s.scene=$("target").value;else s.light=$("target").value;
 if(kind==="power")s.power=$("power").value;
 if(kind==="color"){if(!/^#[0-9a-f]{6}$/i.test($("hex").value)){$("status").textContent="Use a six-digit hex color.";return;}s.color=$("hex").value;s.colorResponse=$("colorResponse").value;}
 if(["color","effect","level"].includes(kind))s.level=Number($("level").value);
 if(kind==="effect"){s.effect=Number($("animation").value==="breathing"?$("effectColor").value:$("animation").value);s.speed=Number($("speed").value);}
 if(send("setSettings",s)){local=s;$("status").textContent="Saved · press key to apply";}
}
window.connectElgatoStreamDeckSocket=(port,uuid,event,info,actionInfo)=>{
 context=uuid;const data=JSON.parse(actionInfo);actionUUID=data.action;kind=actionUUID.split('.').at(-1);local=data.payload.settings||{};
 $("heading").textContent=labels[kind]||"KS Light";
 $("targetLabel").textContent=kind==="scene"?"Scene":"Light";
 for(const section of ["power","color","effect"])$(section+"Section").hidden=kind!==section;
 $("levelSection").hidden=!["color","effect","level"].includes(kind);$("brightnessHint").hidden=kind!=="level";
 $("power").value=local.power||"toggle";$("color").value=local.color||"#ff7800";$("hex").value=$("color").value.toUpperCase();
 $("colorResponse").value=local.colorResponse||(local.color?"raw":"balanced");
 $("level").value=local.level??50;$("speed").value=local.speed??35;
 $("animation").value=local.effect>=132||local.effect===undefined?"breathing":String(local.effect);
 $("effectColor").value=String(local.effect>=132?local.effect:137);updateLabels();
 socket=new WebSocket(`ws://127.0.0.1:${port}`);
 socket.onopen=()=>{socket.send(JSON.stringify({event,uuid}));send("getGlobalSettings");refresh();};
 socket.onmessage=message=>{
  const data=JSON.parse(message.data);
  if(data.event==="didReceiveGlobalSettings"){
   global=data.payload.settings||{};loaded=true;
   for(const id of ["python","repository","config"])if(!$(id).value)$(id).value=global.connection?.[id]||"";
  }
  if(data.event==="sendToPropertyInspector"&&data.payload.event==="catalog"&&data.payload.requestId===requestId){
   const result=data.payload;if(result.error){$("status").textContent=result.error;return;}
   choices=(kind==="scene"?result.scenes:result.lights).filter(item=>kind!=="color"||item.capabilities?.rgb).filter(item=>kind!=="effect"||item.capabilities?.native_effects).filter(item=>kind!=="level"||item.capabilities?.brightness);
   const wanted=kind==="scene"?local.scene:local.light;
   $("target").replaceChildren(new Option(choices.length?"Choose…":"None available",""),...choices.map(item=>new Option(item.name,item.id)));
   if(choices.some(item=>item.id===wanted))$("target").value=wanted;
   else if(!wanted&&choices.length===1)$("target").value=choices[0].id;
   $("status").textContent=choices.length?"Connected":"No compatible targets in this hub.";
   // Never substitute a different device for a previously saved target.
   if(wanted&&!choices.some(item=>item.id===wanted))$("status").textContent="Saved target unavailable. Choose a replacement.";
   else if($("target").value)save();
  }
 };
};
$("refresh").onclick=refresh;
for(const id of ["target","power","animation","effectColor","level","speed","colorResponse"])$(id).onchange=save;
for(const id of ["level","speed"])$(id).oninput=updateLabels;
$("color").oninput=()=>{$("hex").value=$("color").value.toUpperCase();};$("color").onchange=save;
$("hex").onchange=()=>{if(/^#[0-9a-f]{6}$/i.test($("hex").value))$("color").value=$("hex").value;save();};
for(const [name,color] of [["Red","#ff0000"],["Amber","#ff5500"],["Green","#00ff00"],["Blue","#0000ff"],["Purple","#b000ff"],["White","#ffffff"]]){
 const button=document.createElement("button");button.title=name;button.setAttribute("aria-label",name);button.style.background=color;
 button.onclick=()=>{$("color").value=color;$("hex").value=color.toUpperCase();save();};$("swatches").append(button);
}
$("saveConnection").onclick=()=>{
 if(!loaded){$("status").textContent="Waiting for shared setup.";return;}
 const connection=Object.fromEntries(["python","repository","config"].map(id=>[id,$(id).value.trim()]));
 if(Object.values(connection).some(v=>!/^(?:[A-Za-z]:[\\/]|\\\\)/.test(v)||/[\r\n\0]/.test(v))){$("status").textContent="Enter full Windows paths.";return;}
 global={...global,connection};send("setGlobalSettings",global);refresh();
};
