let socket, context, local={}, global={}, loaded=false, dialMode=false;
const paths=["python","repository","config"];
const element=id=>document.getElementById(id);
const shared=()=>element("shared").checked;
const values=()=>Object.fromEntries(paths.map(id=>[id,element(id).value.trim()]));
const validPaths=s=>paths.every(id=>typeof s[id]==="string" && /^(?:[A-Za-z]:[\\/]|\\\\)/.test(s[id]) && !/[\r\n\0]/.test(s[id]));
function send(event,payload){
  if(socket?.readyState!==WebSocket.OPEN){element("status").textContent="Stream Deck is disconnected.";return false;}
  socket.send(JSON.stringify({event,context,...(payload===undefined?{}:{payload})}));return true;
}
function render(){
  const connection=shared()?(global.connection || {}):local;
  paths.forEach(id=>element(id).value=connection[id] || "");
  element("saveConnection").hidden=!shared();
  element("scope").textContent=shared()?"Saving this connection affects every key using shared setup. Save shared paths separately before saving this key.":"These paths belong only to this key. Existing keys keep their own setup.";
  element("saveConnection").disabled=!loaded;
}
window.connectElgatoStreamDeckSocket=(port,uuid,event,info,actionInfo)=>{
  context=uuid;const infoData=JSON.parse(actionInfo);local=infoData.payload.settings || {};dialMode=infoData.action==="dev.kslight.controller.dial";
  element("shared").checked=local.useShared===true;element("action").value=dialMode?(local.actions||[]).join(", "):local.action || "";
  if(element("continuous"))element("continuous").checked=local.continuous===true;
  if(element("showState"))element("showState").checked=local.showState===true;
  if(dialMode){element("action").placeholder="desk-on, reading, purple-breathing, desk-off";}
  render();
  socket=new WebSocket(`ws://127.0.0.1:${port}`);
  socket.onopen=()=>{socket.send(JSON.stringify({event,uuid}));send("getGlobalSettings");};
  socket.onmessage=message=>{
    const data=JSON.parse(message.data);
    if(data.event==="didReceiveGlobalSettings"){
      global=data.payload.settings || {};loaded=true;
      // Do not overwrite edits with late replies; explicit mode changes load saved paths.
      if(shared() && paths.every(id=>!element(id).value))render();
      element("saveConnection").disabled=false;
    }
    if(data.event==="didReceiveSettings")local=data.payload.settings || {};
  };
};
element("shared").onchange=()=>render();
element("saveConnection").onclick=()=>{
  if(!loaded){element("status").textContent="Waiting for shared settings.";return;}
  const connection=values();
  if(!validPaths(connection)){element("status").textContent="Enter full Windows paths for the shared connection.";return;}
  const updated={...global,connection};
  if(send("setGlobalSettings",updated)){global=updated;element("status").textContent="Shared setup sent to Stream Deck. Save this key to select its action.";}
};
element("save").onclick=()=>{
  const action=element("action").value.trim();
  const actions=dialMode?action.split(",").map(v=>v.trim()):[action];
  if(actions.length>32||new Set(actions).size!==actions.length||actions.some(v=>!/^[a-zA-Z0-9_-]{1,64}$/.test(v))){element("status").textContent="Enter valid, unique action names (up to 32 for a dial).";return;}
  const connection=shared()?global.connection:values();
  if((shared()&&!loaded)||!connection||!validPaths(connection)){element("status").textContent="Save a valid connection first.";return;}
  if(shared()&&paths.some(id=>values()[id]!==connection[id])){element("status").textContent="Save shared connection changes first.";return;}
  // Retain private per-key paths when opting in, so opting out can restore them.
  const settings=shared()?{...local,action,useShared:true}:{...local,...connection,action,useShared:false};
  if(dialMode){settings.actions=actions;delete settings.action;}
  if(element("continuous"))settings.continuous=element("continuous").checked;
  if(element("showState"))settings.showState=element("showState").checked;
  if(send("setSettings",settings)){local=settings;element("status").textContent="Key setup sent to Stream Deck.";}
};
