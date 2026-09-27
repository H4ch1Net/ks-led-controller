import streamDeck, {action, SingletonAction} from "@elgato/streamdeck";
import {SharedController} from "./runner.mjs";
import {DialController} from "./dial.mjs";
const controller=new SharedController();
const dials=new DialController();
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
streamDeck.actions.registerAction(new RunAction());
streamDeck.actions.registerAction(new DialAction());
let globalRevision=0;
streamDeck.settings.onDidReceiveGlobalSettings(ev=>{
  globalRevision++;
  void controller.update(ev.settings);
  void dials.update(ev.settings);
});
streamDeck.connect().then(async()=>{
  const revision=globalRevision;
  const saved=await streamDeck.settings.getGlobalSettings();
  if(revision===globalRevision) await Promise.all([controller.update(saved),dials.update(saved)]);
});
