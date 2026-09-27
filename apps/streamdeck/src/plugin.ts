import streamDeck, {action, SingletonAction} from "@elgato/streamdeck";
import {SharedController} from "./runner.mjs";
import {DialController} from "./dial.mjs";
import {DirectController,catalog,connectionSettings} from "./direct.mjs";
const controller=new SharedController();
const dials=new DialController();
const direct=new DirectController();

class DirectAction extends SingletonAction {
  kind="";
  local(ev){return {...ev.payload.settings,kind:this.kind};}
  async onWillAppear(ev){if(ev.action.isKey()) await direct.ready(ev.action,this.local(ev));}
  async onDidReceiveSettings(ev){if(ev.action.isKey()) await direct.ready(ev.action,this.local(ev));}
  onWillDisappear(ev){direct.disappear(ev.action);}
  async onKeyDown(ev){if(ev.action.isKey()) await direct.press(ev.action,this.local(ev));}
}
@action({UUID:"dev.kslight.controller.power"})
class PowerAction extends DirectAction {kind="power";}
@action({UUID:"dev.kslight.controller.color"})
class ColorAction extends DirectAction {kind="color";}
@action({UUID:"dev.kslight.controller.effect"})
class EffectAction extends DirectAction {kind="effect";}
@action({UUID:"dev.kslight.controller.level"})
class LevelAction extends DirectAction {kind="brightness";}
@action({UUID:"dev.kslight.controller.scene"})
class SceneAction extends DirectAction {kind="scene";}
@action({UUID:"dev.kslight.controller.run"})
class RunAction extends SingletonAction {
  async onWillAppear(ev){if(ev.action.isKey()) await controller.ready(ev.action,ev.payload.settings);}
  async onDidReceiveSettings(ev){if(ev.action.isKey()) await controller.ready(ev.action,ev.payload.settings);}
  onWillDisappear(ev){controller.disappear(ev.action);}
  async onKeyDown(ev){if(ev.action.isKey()) await controller.press(ev.action,ev.payload.settings);}
}
@action({UUID:"dev.kslight.controller.dial"})
class DialAction extends SingletonAction {
 async onWillAppear(ev){if(ev.action.isDial()) await dials.ready(ev.action,ev.payload.settings);}
 async onDidReceiveSettings(ev){if(ev.action.isDial()) await dials.ready(ev.action,ev.payload.settings);}
 onWillDisappear(ev){dials.disappear(ev.action);}
 async onDialRotate(ev){await dials.rotate(ev.action,ev.payload.ticks);}
 async onDialDown(ev){await dials.press(ev.action);}
}
@action({UUID:"dev.kslight.controller.brightness"})
class BrightnessAction extends SingletonAction {
 async onWillAppear(ev){if(ev.action.isDial()) await dials.ready(ev.action,{...ev.payload.settings,brightnessMode:true});}
 async onDidReceiveSettings(ev){if(ev.action.isDial()) await dials.ready(ev.action,{...ev.payload.settings,brightnessMode:true});}
 onWillDisappear(ev){dials.disappear(ev.action);}
 async onDialRotate(ev){await dials.rotate(ev.action,ev.payload.ticks);}
 async onDialDown(ev){await dials.press(ev.action);}
}
streamDeck.actions.registerAction(new BrightnessAction());
streamDeck.actions.registerAction(new PowerAction());
streamDeck.actions.registerAction(new ColorAction());
streamDeck.actions.registerAction(new EffectAction());
streamDeck.actions.registerAction(new LevelAction());
streamDeck.actions.registerAction(new SceneAction());
streamDeck.actions.registerAction(new RunAction());
streamDeck.actions.registerAction(new DialAction());
let globalRevision=0;
streamDeck.settings.onDidReceiveGlobalSettings(ev=>{
  globalRevision++;
  void controller.update(ev.settings);
  void dials.update(ev.settings);
  void direct.update(ev.settings);
});
streamDeck.ui.onSendToPlugin(async ev=>{
  if(ev.payload?.event!=="catalog"||typeof ev.payload?.requestId!=="string")return;
  const selected=ev.action.id;
  try {
    // A single existing connection can be reused without asking for paths again.
    // Multiple legacy setups remain ambiguous and require choosing shared setup.
    let saved=await streamDeck.settings.getGlobalSettings();
    if(!saved.connection) {
      const connections=new Map();
      for(const {settings} of controller.keys.values()) {
        try {const s=connectionSettings(settings);const c={python:s.python,repository:s.repository,config:s.config};connections.set(JSON.stringify(c),c);}catch{}
      }
      if(connections.size===1) {
        saved={...saved,connection:[...connections.values()][0]};
        await streamDeck.settings.setGlobalSettings(saved);
        await direct.update(saved);
      }
    }
    const choices=await catalog(saved.connection);
    if(streamDeck.ui.action?.id===selected)await streamDeck.ui.sendToPropertyInspector({event:"catalog",requestId:ev.payload.requestId,...choices});
  } catch {
    if(streamDeck.ui.action?.id===selected)await streamDeck.ui.sendToPropertyInspector({event:"catalog",requestId:ev.payload.requestId,error:"Hub unavailable. Check shared connection."});
  }
});
streamDeck.connect().then(async()=>{
  const revision=globalRevision;
  const saved=await streamDeck.settings.getGlobalSettings();
  if(revision===globalRevision) await Promise.all([controller.update(saved),dials.update(saved),direct.update(saved)]);
});
