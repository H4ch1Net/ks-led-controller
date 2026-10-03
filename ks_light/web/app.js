// KS Light hub dashboard. Talks only to this hub's /api/v1 with the bearer token the user enters.
const API = "/api/v1";
const TOKEN_KEY = "ks-light-token";
const ACCENT_KEY = "ks-light-accent";
const ACCENTS = { lime: "#d4efa3", ocean: "#8cd5ff", violet: "#d0b4ff", rose: "#ffb4cc", amber: "#ffd08a" };
const PRESETS = [
  ["Warm white", [255, 170, 90]], ["Daylight", [235, 245, 255]], ["Red", [255, 40, 40]], ["Orange", [255, 140, 0]],
  ["Green", [40, 220, 90]], ["Cyan", [0, 220, 255]], ["Blue", [40, 80, 255]], ["Purple", [180, 70, 255]], ["Pink", [255, 80, 170]],
];
const TERMINAL = new Set(["succeeded", "failed", "cancelled"]);
const ERRORS = {
  unauthorized: "The hub rejected this token.",
  read_only_credential: "This credential is read-only.",
  target_not_allowed: "This credential cannot control that light.",
  queue_full: "That light already has several commands waiting. Try again shortly.",
  operation_capacity: "The hub is busy. Try again shortly.",
  configuration_changing: "The hub configuration is being saved. Try again.",
  remembered_color_required: "Choose a color first; the hub has no remembered color for this light.",
  unsupported_capability: "This light does not support that control.",
  write_failed: "Delivery failed. The light state is now unknown.",
  partial_failure: "Some lights did not receive the command.",
  members_failed: "No light received the command.",
};

const $ = (selector, root = document) => root.querySelector(selector);
const state = {
  token: null, health: null, caps: null, lights: new Map(), groups: [], scenes: [],
  cursor: 0, instance: null, ops: new Map(), mine: new Set(), loop: 0,
};

// ---------- utilities ----------
const hex = (rgb) => "#" + rgb.map((v) => v.toString(16).padStart(2, "0")).join("");
const parseHex = (value) => [1, 3, 5].map((i) => parseInt(value.slice(i, i + 2), 16));
const message = (code) => ERRORS[code] || `Request failed (${code}).`;
const effectName = (id) => state.caps?.native_effects?.find((e) => e.id === id)?.name || `Effect ${id}`;

function readStore(storage, key) {
  try { return storage.getItem(key); } catch { return null; }
}
function writeStore(storage, key, value) {
  try { value === null ? storage.removeItem(key) : storage.setItem(key, value); } catch { /* storage blocked */ }
}

class HubError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}

async function api(path, { method = "GET", body, signal } = {}) {
  const headers = { Authorization: `Bearer ${state.token}` };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    headers["Idempotency-Key"] = "web-" + crypto.randomUUID();
  }
  let response;
  try {
    response = await fetch(API + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal, cache: "no-store" });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    throw new HubError(0, "offline");
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401) signOut("The hub rejected this token.");
    throw new HubError(response.status, data.error || String(response.status));
  }
  return data;
}

function svgUse(id, className = "icon") {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", className);
  svg.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", "#" + id);
  svg.append(use);
  return svg;
}

function led(tone) {
  const node = document.createElement("span");
  node.className = "led" + (tone ? " " + tone : "");
  node.setAttribute("aria-hidden", "true");
  return node;
}

function toast(text, bad = false) {
  const node = document.createElement("div");
  node.className = "toast" + (bad ? " bad" : "");
  const label = document.createElement("span");
  label.textContent = text;
  node.append(led(bad ? "bad" : "ok"), label);
  $("#toasts").append(node);
  setTimeout(() => {
    node.classList.add("leaving");
    setTimeout(() => node.remove(), 170);
  }, bad ? 6000 : 3200);
}

// ---------- accent ----------
function setAccent(name) {
  if (!ACCENTS[name]) name = "lime";
  document.documentElement.dataset.accent = name;
  writeStore(localStorage, ACCENT_KEY, name);
  for (const button of $("#accents").children) button.setAttribute("aria-checked", String(button.dataset.accent === name));
}
function renderAccents() {
  const group = $("#accents");
  for (const [name, color] of Object.entries(ACCENTS)) {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("role", "radio");
    button.dataset.accent = name;
    button.style.setProperty("--swatch", color);
    button.title = name[0].toUpperCase() + name.slice(1);
    button.setAttribute("aria-label", button.title);
    button.addEventListener("click", () => setAccent(name));
    group.append(button);
  }
  setAccent(readStore(localStorage, ACCENT_KEY) || "lime");
}

// ---------- sign-in ----------
function showSignIn(error) {
  $("#app").hidden = true;
  $("#signin").hidden = false;
  const node = $("#signin-error");
  node.hidden = !error;
  node.textContent = error || "";
  $("#token").focus();
}

function signOut(reason) {
  state.loop++;
  state.token = null;
  writeStore(sessionStorage, TOKEN_KEY, null);
  writeStore(localStorage, TOKEN_KEY, null);
  showSignIn(reason);
}

function showSkeleton() {
  $("#signin").hidden = true;
  $("#app").hidden = false;
  const grid = $("#lights");
  if (grid.children.length) return;
  for (let i = 0; i < 3; i++) {
    const card = document.createElement("div");
    card.className = "card skeleton";
    card.setAttribute("aria-hidden", "true");
    const head = document.createElement("div");
    head.className = "sk-head";
    const lens = document.createElement("i");
    lens.className = "sk-lens";
    const title = document.createElement("i");
    title.className = "sk-line";
    title.style.width = "45%";
    head.append(lens, title);
    card.append(head);
    for (const width of ["100%", "70%", "85%"]) {
      const line = document.createElement("i");
      line.className = "sk-line";
      line.style.width = width;
      card.append(line);
    }
    grid.append(card);
  }
}

async function connect(token, remember, automatic = false) {
  state.token = token;
  const button = $("#signin-submit");
  button.disabled = true;
  button.classList.add("loading");
  $(".text", button).textContent = "Connecting";
  if (automatic) showSkeleton();
  try {
    await refreshAll();
  } catch (error) {
    state.token = null;
    showSignIn(error.code === "offline" ? "The hub is not reachable." : error.code === "unauthorized" ? "The hub rejected this token." : message(error.code));
    return;
  } finally {
    button.disabled = false;
    button.classList.remove("loading");
    $(".text", button).textContent = "Connect";
  }
  writeStore(remember ? localStorage : sessionStorage, TOKEN_KEY, token);
  $("#signin").hidden = true;
  $("#app").hidden = false;
  $("#token").value = "";
  watchEvents(++state.loop);
}

// ---------- data ----------
async function refreshAll() {
  const [health, caps, lights, groups, scenes] = await Promise.all([
    api("/health"), api("/capabilities"), api("/lights"), api("/groups"), api("/scenes"),
  ]);
  Object.assign(state, { health, caps, groups: groups.groups, scenes: scenes.scenes, cursor: lights.cursor, instance: lights.instance });
  state.lights = new Map(lights.lights.map((light) => [light.id, light]));
  render();
}

async function refreshLight(id) {
  try {
    state.lights.set(id, await api(`/lights/${encodeURIComponent(id)}`));
    renderLight(id);
    updateCount();
  } catch { /* the next event or resync fixes it */ }
}

async function refreshHealth() {
  try { state.health = await api("/health"); renderStatus(); } catch { /* shown by the event loop */ }
}

async function watchEvents(loop) {
  let delay = 1000;
  let healthTick = 0;
  while (loop === state.loop) {
    try {
      const data = await api(`/events?after=${state.cursor}&instance=${state.instance}&wait=25`);
      if (loop !== state.loop) return;
      setBanner(null);
      delay = 1000;
      state.cursor = data.cursor;
      const lights = new Set();
      const ops = new Set();
      for (const event of data.events) {
        if (event.type === "light.updated") lights.add(event.target_id);
        if (event.operation_id) ops.add(event.operation_id);
      }
      await Promise.all([...lights].map(refreshLight).concat([...ops].map(refreshOperation)));
      if (++healthTick % 4 === 0) refreshHealth();
    } catch (error) {
      if (loop !== state.loop) return;
      if (error.code === "resync_required") {
        try { await refreshAll(); continue; } catch { /* fall through to retry */ }
      }
      setBanner("Lost contact with the hub. Retrying.", true);
      await new Promise((resolve) => setTimeout(resolve, delay));
      delay = Math.min(delay * 2, 15000);
      try { await refreshAll(); } catch { /* keep retrying */ }
    }
  }
}

// ---------- commands ----------
function describeTarget(op) {
  if (op.target_type === "scene") return state.scenes.find((s) => s.id === op.target_id)?.name || op.target_id;
  if (op.target_type === "group") return state.groups.find((g) => g.id === op.target_id)?.name || op.target_id;
  return state.lights.get(op.target_id)?.name || op.target_id;
}

async function refreshOperation(id) {
  let op;
  try { op = await api(`/operations/${encodeURIComponent(id)}`); } catch { return; }
  const known = state.ops.get(id);
  state.ops.set(id, { ...op, label: known?.label, at: known?.at || new Date() });
  if (state.ops.size > 40) state.ops.delete(state.ops.keys().next().value);
  if (TERMINAL.has(op.status) && state.mine.has(id)) {
    state.mine.delete(id);
    const label = known?.label || "Command";
    if (op.status === "succeeded") toast(`${label}: ${op.confirmation === "simulated" ? "simulated" : "sent"}`);
    else toast(`${label}: ${message(op.error || op.status)}`, true);
    setBusy(op);
  }
  renderActivity();
}

function setBusy(op, busy = false) {
  const targets = op.members ? op.members.map((m) => m.target_id) : [op.target_id];
  for (const id of targets) {
    const card = document.querySelector(`[data-light="${CSS.escape(id)}"]`);
    if (!card) continue;
    card.classList.toggle("busy", busy);
    $(".pending", card).hidden = !busy;
  }
}

async function send(path, body, label, targets) {
  try {
    const result = await api(path, { method: path.endsWith("/state") ? "PATCH" : "POST", body });
    const op = { operation_id: result.operation_id, status: result.status, label, at: new Date(), target_id: targets[0],
                 members: targets.length > 1 ? targets.map((t) => ({ target_id: t })) : undefined };
    state.mine.add(result.operation_id);
    state.ops.set(result.operation_id, op);
    setBusy(op, true);
    renderActivity();
    pollOperation(result.operation_id);
  } catch (error) {
    if (error.code !== "unauthorized") toast(`${label}: ${message(error.code)}`, true);
  }
}

// Events normally report completion; a short poll covers a missed event.
async function pollOperation(id) {
  for (let i = 0; i < 40 && state.mine.has(id); i++) {
    await new Promise((resolve) => setTimeout(resolve, i < 10 ? 150 : 500));
    if (state.mine.has(id)) await refreshOperation(id);
  }
}

const lightPath = (id) => `/lights/${encodeURIComponent(id)}`;

function setPower(light, on) {
  send(`${lightPath(light.id)}/state`, { power: on }, `${light.name} ${on ? "on" : "off"}`, [light.id]);
}

function setColor(light, rgb) {
  const body = { power: true, rgb };
  if (light.capabilities.brightness) body.brightness = light.last_sent?.brightness || 100;
  send(`${lightPath(light.id)}/state`, body, `${light.name} color`, [light.id]);
}

function setBrightness(light, value) {
  const last = light.last_sent || {};
  const body = { power: true, brightness: value };
  if (!last.rgb && last.native_effect === undefined) body.rgb = [255, 255, 255];
  send(`${lightPath(light.id)}/state`, body, `${light.name} brightness ${value}%`, [light.id]);
}

function startEffect(light, effect, speed) {
  const brightness = Math.max(1, light.last_sent?.brightness || 60);
  send(`${lightPath(light.id)}/effects/native`, { effect, speed, brightness }, `${light.name}: ${effectName(effect)}`, [light.id]);
}

// ---------- rendering ----------
// Colors the lamp firmware uses for each built-in breathing effect; 130/131 cycle hues.
const EFFECT_COLORS = { 132: "#ff3b3b", 133: "#38e070", 134: "#3d6bff", 135: "#ffd23d", 136: "#3de0ff", 137: "#b25cff", 138: "#f2f4ff" };

function setBanner(text, bad = false) {
  const node = $("#banner");
  node.hidden = !text;
  $(".text", node).textContent = text || "";
  $("use", node).setAttribute("href", bad ? "#i-alert" : "#i-flask");
  node.classList.toggle("bad", bad);
}

function indicator(label, value, tone) {
  const node = document.createElement("span");
  node.className = "indicator";
  const strong = document.createElement("b");
  strong.textContent = value;
  node.append(led(tone), label + " ", strong);
  return node;
}

function renderStatus() {
  const { health } = state;
  const status = $("#status");
  status.replaceChildren();
  if (!health) return;
  const simulated = health.mode === "simulation";
  status.append(indicator("Mode", simulated ? "Simulation" : "Bluetooth", simulated ? "warn" : "ok"));
  status.append(indicator("Hub", health.status === "ok" ? "Healthy" : "Degraded", health.status === "ok" ? "ok" : "bad"));
  if (health.mqtt.state !== "disabled") status.append(indicator("MQTT", health.mqtt.state, health.mqtt.state === "online" ? "ok" : "bad"));
  if (health.persistence.enabled) status.append(indicator("State", health.persistence.status === "ok" ? "Saved" : "Not saved", health.persistence.status === "ok" ? "ok" : "bad"));
  setBanner(simulated ? "Simulation mode. Commands are not sent to real lights." : null);
}

function describeLast(light) {
  const last = light.last_sent;
  if (!last) return "No command sent yet";
  if (last.power === false) return "Off";
  if (last.native_effect !== undefined) return `${effectName(last.native_effect)} · ${last.brightness}%`;
  if (last.rgb) return `${hex(last.rgb).toUpperCase()}${light.capabilities.brightness ? ` · ${last.brightness}%` : ""}`;
  return last.power ? "On" : "Unknown";
}

function syncFader(input) {
  const min = Number(input.min), max = Number(input.max);
  input.closest(".fader").style.setProperty("--pct", `${((Number(input.value) - min) / (max - min)) * 100}%`);
  input.closest(".fader").querySelector("output").textContent = input.value + "%";
}

function buildLight(light) {
  const card = $("#light-template").content.firstElementChild.cloneNode(true);
  card.dataset.light = light.id;
  $("h3", card).textContent = light.name;
  $(".rocker", card).setAttribute("aria-label", `${light.name} power`);
  for (const button of card.querySelectorAll("[data-power]")) {
    button.addEventListener("click", () => setPower(state.lights.get(light.id), button.dataset.power === "on"));
  }
  const slider = $("[data-cap=brightness] input", card);
  slider.setAttribute("aria-label", `${light.name} brightness`);
  slider.addEventListener("input", () => syncFader(slider));
  slider.addEventListener("change", () => setBrightness(state.lights.get(light.id), Number(slider.value)));

  const chips = $(".chips", card);
  chips.setAttribute("aria-label", `${light.name} colors`);
  for (const [name, rgb] of PRESETS) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.dataset.rgb = hex(rgb);
    chip.style.setProperty("--chip", hex(rgb));
    chip.title = name;
    chip.setAttribute("aria-label", name);
    chip.addEventListener("click", () => setColor(state.lights.get(light.id), rgb));
    chips.append(chip);
  }
  const custom = document.createElement("label");
  custom.className = "chip custom";
  custom.title = "Custom color";
  const picker = document.createElement("input");
  picker.type = "color";
  picker.setAttribute("aria-label", `${light.name} custom color`);
  picker.addEventListener("change", () => setColor(state.lights.get(light.id), parseHex(picker.value)));
  custom.append(picker);
  chips.append(custom);

  const select = $(".effects select", card);
  for (const effect of state.caps.native_effects || []) select.add(new Option(effect.name, effect.id));
  select.value = "137";
  const speed = $("[data-role=speed]", card);
  speed.setAttribute("aria-label", `${light.name} effect speed`);
  syncFader(speed);
  speed.addEventListener("input", () => syncFader(speed));
  $("[data-role=start]", card).addEventListener("click", () => startEffect(state.lights.get(light.id), Number(select.value), Number(speed.value)));
  return card;
}

function renderLight(id) {
  const light = state.lights.get(id);
  let card = document.querySelector(`[data-light="${CSS.escape(id)}"]`);
  if (!card) {
    card = buildLight(light);
    $("#lights").append(card);
  }
  const caps = light.capabilities;
  for (const section of card.querySelectorAll("[data-cap]")) section.hidden = !caps[section.dataset.cap];
  $(".meta", card).textContent = light.prefix + (light.restored ? " · restored" : "");
  const last = light.last_sent || {};
  const effect = last.native_effect;
  const off = last.power === false;
  const lit = !off && (last.power === true || Boolean(last.rgb) || effect !== undefined);
  for (const button of card.querySelectorAll("[data-power]")) {
    button.setAttribute("aria-pressed", String(button.dataset.power === "on" ? lit : off));
  }

  // The lens and light pool show the last-sent light: color, brightness and effect motion.
  const lens = $(".lens", card);
  const color = lit ? (last.rgb ? hex(last.rgb) : EFFECT_COLORS[effect] || "#ff4d4d") : "";
  const level = caps.brightness ? (last.brightness ?? 100) / 100 : 1;
  const speed = last.speed ?? 35;
  lens.classList.toggle("lit", lit);
  lens.classList.toggle("breathing", lit && effect >= 132);
  lens.classList.toggle("fading", lit && (effect === 130 || effect === 131));
  for (const node of [lens, card]) {
    node.style.setProperty("--c", color || "transparent");
    node.style.setProperty("--b", level.toFixed(2));
  }
  card.style.setProperty("--lit", lit ? "1" : "0");
  lens.style.setProperty("--period", `${(1.2 + ((100 - speed) / 100) * 4.8) * (effect < 132 ? 2 : 1)}s`);

  const chosen = !off && last.rgb ? hex(last.rgb) : "";
  for (const chip of card.querySelectorAll(".chip[data-rgb]")) chip.setAttribute("aria-pressed", String(chip.dataset.rgb === chosen));
  const slider = $("[data-cap=brightness] input", card);
  if (caps.brightness && document.activeElement !== slider) {
    slider.value = last.brightness || 100;
    syncFader(slider);
  }
  if (effect !== undefined) $(".effects select", card).value = String(effect);
  const footer = $(".last", card);
  footer.replaceChildren(led(lit ? "ok" : off ? "" : "warn"));
  const text = document.createElement("span");
  text.className = "text";
  text.textContent = describeLast(light);
  footer.append(text);
}

function segmentsFor(actions) {
  const strip = document.createElement("span");
  strip.className = "strip";
  strip.setAttribute("aria-hidden", "true");
  for (const { type, body } of actions.slice(0, 8)) {
    const segment = document.createElement("i");
    if (type === "native") {
      if (EFFECT_COLORS[body.effect]) segment.style.setProperty("--seg", EFFECT_COLORS[body.effect]);
      else segment.className = "effect";
    } else if (body.power === false) segment.className = "off";
    else segment.style.setProperty("--seg", body.rgb ? hex(body.rgb) : "#e9ece6");
    strip.append(segment);
  }
  return strip;
}

function sceneTile(scene) {
  const item = document.createElement("li");
  const button = document.createElement("button");
  button.type = "button";
  button.className = "scene";
  const count = new Set(scene.actions.map((a) => a.light)).size;
  button.setAttribute("aria-label", `Apply scene ${scene.name}, ${count} light${count === 1 ? "" : "s"}`);
  const name = document.createElement("strong");
  name.textContent = scene.name;
  const foot = document.createElement("span");
  foot.className = "apply";
  const lights = document.createElement("span");
  lights.textContent = `${count} light${count === 1 ? "" : "s"}`;
  const apply = document.createElement("span");
  apply.textContent = "Apply";
  foot.append(lights, apply);
  button.append(segmentsFor(scene.actions), name, foot);
  button.addEventListener("click", () => send(`/scenes/${encodeURIComponent(scene.id)}/apply`, {}, `Scene ${scene.name}`, scene.actions.map((a) => a.light)));
  item.append(button);
  return item;
}

function row(title, detail, actions) {
  const item = document.createElement("li");
  item.className = "row";
  const name = document.createElement("div");
  name.className = "name";
  const strong = document.createElement("strong");
  strong.textContent = title;
  const span = document.createElement("span");
  span.textContent = detail;
  name.append(strong, span);
  const buttons = document.createElement("div");
  buttons.className = "actions";
  buttons.setAttribute("role", "group");
  buttons.setAttribute("aria-label", `${title} power`);
  for (const [text, label, handler] of actions) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "button small";
    button.textContent = text;
    button.setAttribute("aria-label", label);
    button.addEventListener("click", handler);
    buttons.append(button);
  }
  item.append(name, buttons);
  return item;
}

function empty(list, text) {
  const item = document.createElement("li");
  item.className = "empty";
  const caption = document.createElement("span");
  caption.textContent = text;
  item.append(svgUse("ill-lamp", "ill"), caption);
  list.append(item);
}

function renderLibrary() {
  const scenes = $("#scenes");
  scenes.replaceChildren(...state.scenes.map(sceneTile));
  if (!state.scenes.length) empty(scenes, "No scenes yet. Add them to the hub library file.");

  const groups = $("#groups");
  groups.replaceChildren();
  for (const group of state.groups) {
    const names = group.members.map((id) => state.lights.get(id)?.name || id).join(", ");
    const path = `/groups/${encodeURIComponent(group.id)}/state`;
    groups.append(row(group.name, names, [
      ["On", `Turn ${group.name} on`, () => send(path, { power: true }, `${group.name} on`, group.members)],
      ["Off", `Turn ${group.name} off`, () => send(path, { power: false }, `${group.name} off`, group.members)],
    ]));
  }
  if (!state.groups.length) empty(groups, "No groups yet.");
}

function renderActivity() {
  const list = $("#activity");
  list.replaceChildren();
  const ops = [...state.ops.values()].reverse();
  for (const op of ops) {
    const item = document.createElement("li");
    item.className = op.status;
    const done = TERMINAL.has(op.status);
    const dot = done ? led(op.status === "succeeded" ? "ok" : "bad") : led("blink");
    dot.removeAttribute("aria-hidden");
    dot.setAttribute("role", "img");
    dot.setAttribute("aria-label", op.status);
    const text = document.createElement("span");
    text.className = "text";
    text.textContent = op.label || `${describeTarget(op)} updated`;
    if (done && op.status !== "succeeded") text.textContent += ` (${op.error || op.status})`;
    const time = document.createElement("time");
    time.dateTime = op.at.toISOString();
    time.textContent = op.at.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    item.append(dot, text, time);
    list.append(item);
  }
  if (!ops.length) empty(list, "Commands from this page and other clients appear here.");
}

function updateCount() {
  const lit = [...state.lights.values()].filter((l) => l.last_sent && l.last_sent.power !== false).length;
  $("#lights-count").textContent = `${state.lights.size} · ${lit} on`;
}

function render() {
  renderStatus();
  const grid = $("#lights");
  for (const node of grid.querySelectorAll(".skeleton")) node.remove();
  grid.removeAttribute("aria-busy");
  const known = new Set(state.lights.keys());
  for (const card of grid.querySelectorAll("[data-light]")) if (!known.has(card.dataset.light)) card.remove();
  for (const id of state.lights.keys()) renderLight(id);
  updateCount();
  renderLibrary();
  renderActivity();
}

// ---------- start ----------
renderAccents();
$("#signin-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const token = $("#token").value.trim();
  if (token.length < 32) return showSignIn("Tokens are at least 32 characters.");
  connect(token, $("#remember").checked);
});
$("#signout").addEventListener("click", () => signOut());
const saved = readStore(sessionStorage, TOKEN_KEY) || readStore(localStorage, TOKEN_KEY);
if (saved) connect(saved, readStore(localStorage, TOKEN_KEY) === saved, true);
else showSignIn();
