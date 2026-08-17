const $ = (id) => document.getElementById(id);

let current = null;
let selectedDays = new Set([0,1,2,3,4,5,6]);
const dayNames = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
let bridgeClockBase = null;
let browserClockBase = null;
let settingsDirty = false;
let settingsWired = false;

function currentBridgeUrl() {
  return (localStorage.getItem("wemoteBridgeUrl") || "").replace(/\/$/, "");
}

function setLastCommand(text) {
  localStorage.setItem("wemoteLastCommand", text);
  if ($("lastCommand")) $("lastCommand").textContent = text;
}

function refreshRemoteBadge() {
  const url = currentBridgeUrl();
  const dot = $("remoteDot");
  const label = $("remoteStatus");
  if (!dot || !label) return;
  if (!url) {
    dot.className = "status-dot warn";
    label.textContent = "NOT LINKED";
    return;
  }
  dot.className = "status-dot ok";
  try {
    const host = new URL(url).hostname;
    label.textContent = host.endsWith(".ts.net") ? "TAILSCALE" : "CONNECTED";
  } catch {
    label.textContent = "CONNECTED";
  }
}

async function api(path, options={}) {
  const base = currentBridgeUrl();
  if (!base) throw new Error("Remote bridge is not linked yet.");
  const res = await fetch(base + path, {
    headers: {"Content-Type":"application/json", ...(options.headers||{})},
    cache: "no-store",
    ...options
  });
  let data = {};
  try { data = await res.json(); } catch {}
  if (!res.ok) throw new Error(data.detail || `Request failed (${res.status})`);
  return data;
}

function showMessage(text, error=false) {
  const el = $("message");
  el.textContent = text;
  el.classList.remove("hidden", "error");
  if (error) el.classList.add("error");
  clearTimeout(showMessage.timer);
  showMessage.timer = setTimeout(() => el.classList.add("hidden"), 4500);
}

function prettyDate(value) {
  if (!value) return "Not scheduled";
  const d = new Date(value);
  return d.toLocaleString([], {weekday:"short", hour:"numeric", minute:"2-digit"});
}

function bridgeNow() {
  if (!bridgeClockBase || !browserClockBase) return new Date();
  return new Date(bridgeClockBase.getTime() + (Date.now() - browserClockBase));
}

function formatDuration(ms) {
  if (ms <= 0) return "00:00:00";
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return [h,m,s].map(v => String(v).padStart(2,"0")).join(":");
}

function tickClock() {
  const now = bridgeNow();
  $("liveClock").textContent = now.toLocaleTimeString([], {hour:"numeric", minute:"2-digit", second:"2-digit"});
  $("liveDate").textContent = now.toLocaleDateString([], {weekday:"long", month:"short", day:"numeric", year:"numeric"});

  const next = current?.next_schedule;
  if (next?.when) {
    const when = new Date(next.when);
    $("nextAction").textContent = `${next.action} | ${when.toLocaleString([], {weekday:"short", hour:"numeric", minute:"2-digit"})}`;
    const delta = when.getTime() - now.getTime();
    $("countdown").textContent = delta > 0 ? formatDuration(delta) : "DUE";
  } else {
    $("nextAction").textContent = "Not scheduled";
    $("countdown").textContent = "--:--:--";
  }
}

function renderDays() {
  const wrap = $("days");
  wrap.innerHTML = "";
  dayNames.forEach((name, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "day" + (selectedDays.has(i) ? " active" : "");
    b.textContent = name;
    b.onclick = () => {
      selectedDays.has(i) ? selectedDays.delete(i) : selectedDays.add(i);
      settingsDirty = true;
      renderDays();
    };
    wrap.appendChild(b);
  });
}

function renderMode(mode) {
  const feeder = mode === "feeder";
  $("feederMode").classList.toggle("active", feeder);
  $("lightMode").classList.toggle("active", !feeder);
  $("feederPanel").classList.toggle("hidden", !feeder);
  $("lightPanel").classList.toggle("hidden", feeder);
  $("feederSettings").classList.toggle("hidden", !feeder);
  $("lightSettings").classList.toggle("hidden", feeder);
}

function renderSchedulerState(s) {
  const running = !!s.scheduler?.running;
  const enabled = !!s.settings?.schedule_enabled;
  const text = !running ? "STOPPED" : enabled ? "ENABLED" : "OFF";
  const cls = !running ? "bad" : enabled ? "ok" : "warn";
  $("schedulerState").textContent = text;
  $("schedulerState").className = cls === "bad" ? "status-bad" : cls === "warn" ? "status-warn" : "status-good";
  $("scheduleDot").className = `status-dot ${cls}`;
}

async function refreshStatus() {
  try {
    const s = await api("/api/status");
    current = s;
    bridgeClockBase = new Date(s.bridge_time);
    browserClockBase = Date.now();

    $("statusDot").className = "status-dot ok";
    $("bridgeStatus").textContent = "ONLINE";
    if ($("appVersion")) $("appVersion").textContent = s.version || "0.5.6";
    $("deviceName").textContent = s.device ? s.device.name : "No Wemo selected";
    renderSchedulerState(s);
    renderMode(s.mode);

    const state = s.device?.state;
    const stateText = state === 1 ? "ON" : state === 0 ? "OFF" : "Unknown";
    $("masterState").textContent = stateText;
    $("masterState").className = "master-state " + (state === 1 ? "is-on" : state === 0 ? "is-off" : "is-unknown");
    $("lightState").textContent = stateText;
    $("feedState").textContent = s.device ? "Ready" : "No device";
    $("lastFeed").textContent = s.last_feed ? new Date(s.last_feed.created_at).toLocaleString() : "Never";

    const nextText = s.next_schedule?.when ? prettyDate(s.next_schedule.when) : "Not scheduled";
    $("nextFeed").textContent = s.mode === "feeder" ? nextText : "-";
    $("nextLight").textContent = s.mode === "light" ? nextText : "-";

    const st = s.settings;
    if (!settingsDirty) {
      $("scheduleEnabled").checked = !!st.schedule_enabled;
      selectedDays = new Set(st.schedule_days || []);
      renderDays();
      $("feederTime").value = st.feeder_time;
      $("pulseSeconds").value = st.feeder_pulse_seconds;
      $("lockoutMinutes").value = st.feeder_lockout_minutes;
      $("lightOnTime").value = st.light_on_time;
      $("lightOffTime").value = st.light_off_time;
    }

    refreshRemoteBadge();
    tickClock();
  } catch (e) {
    $("statusDot").className = "status-dot bad";
    $("bridgeStatus").textContent = currentBridgeUrl() ? "UNAVAILABLE" : "NOT LINKED";
    $("scheduleDot").className = "status-dot bad";
    $("schedulerState").textContent = "OFFLINE";
    $("schedulerState").className = "status-bad";
    refreshRemoteBadge();
  }
}

async function refreshDevices() {
  try {
    const data = await api("/api/devices");
    const select = $("deviceSelect");
    select.innerHTML = "";
    if (!data.devices.length) {
      const o = document.createElement("option");
      o.textContent = "No Wemo devices found";
      o.value = "";
      select.appendChild(o);
      return;
    }
    data.devices.forEach(d => {
      const o = document.createElement("option");
      o.value = d.id;
      o.textContent = `${d.name} (${d.model})`;
      o.selected = d.id === data.selected_device_id;
      select.appendChild(o);
    });
  } catch {}
}

async function refreshEvents() {
  try {
    const data = await api("/api/events?limit=20");
    const box = $("events");
    box.innerHTML = "";
    if (!data.events.length) {
      box.textContent = "No activity yet.";
      return;
    }
    data.events.forEach(ev => {
      const row = document.createElement("div");
      row.className = "event";
      const t = document.createElement("span");
      t.textContent = new Date(ev.created_at).toLocaleString();
      const d = document.createElement("span");
      d.textContent = `${ev.event_type}: ${ev.detail || ""}`;
      row.append(t, d);
      box.appendChild(row);
    });
  } catch {}
}

$("saveBridgeUrl").onclick = async () => {
  const raw = $("bridgeUrl").value.trim().replace(/\/$/, "");
  if (!/^https:\/\/[a-zA-Z0-9.-]+$/.test(raw)) {
    showMessage("Enter the full HTTPS bridge URL.", true);
    return;
  }
  localStorage.setItem("wemoteBridgeUrl", raw);
  refreshRemoteBadge();
  showMessage("Remote bridge saved.");
  await refreshStatus();
  await refreshDevices();
  await refreshEvents();
};

$("feederMode").onclick = async () => {
  try {
    await api("/api/mode", {method:"POST", body:JSON.stringify({mode:"feeder"})});
    await refreshStatus();
    showMessage("Pet Feeder mode enabled. Plug forced OFF for safety.");
  } catch(e) { showMessage(e.message, true); }
};

$("lightMode").onclick = async () => {
  try {
    await api("/api/mode", {method:"POST", body:JSON.stringify({mode:"light"})});
    await refreshStatus();
    showMessage("Light Timer mode enabled.");
  } catch(e) { showMessage(e.message, true); }
};

$("masterOn").onclick = async () => {
  try {
    await api("/api/power", {method:"POST", body:JSON.stringify({state:"on"})});
    $("masterState").textContent = "ON";
    $("masterState").className = "master-state is-on";
    $("lightState").textContent = "ON";
    setLastCommand(`ON | ${new Date().toLocaleTimeString([], {hour:"numeric", minute:"2-digit", second:"2-digit"})}`);
    showMessage("Master power ON.");
    setTimeout(refreshStatus, 700);
    await refreshEvents();
  } catch(e) { showMessage(e.message, true); }
};

$("masterOff").onclick = async () => {
  try {
    await api("/api/power", {method:"POST", body:JSON.stringify({state:"off"})});
    $("masterState").textContent = "OFF";
    $("masterState").className = "master-state is-off";
    $("lightState").textContent = "OFF";
    setLastCommand(`OFF | ${new Date().toLocaleTimeString([], {hour:"numeric", minute:"2-digit", second:"2-digit"})}`);
    showMessage("Master power OFF.");
    setTimeout(refreshStatus, 700);
    await refreshEvents();
  } catch(e) { showMessage(e.message, true); }
};

$("feedNow").onclick = async () => {
  const b = $("feedNow");
  b.disabled = true;
  b.textContent = "FEEDING...";
  try {
    const r = await api("/api/feed", {method:"POST"});
    setLastCommand(`FEED | ${new Date().toLocaleTimeString([], {hour:"numeric", minute:"2-digit", second:"2-digit"})}`);
    showMessage(`Feed cycle complete (${r.pulse_seconds}s pulse).`);
    await refreshStatus();
    await refreshEvents();
  } catch(e) {
    showMessage(e.message, true);
  } finally {
    b.disabled = false;
    b.textContent = "FEED NOW";
  }
};

$("saveSettings").onclick = async () => {
  const body = {
    feeder_pulse_seconds: Number($("pulseSeconds").value),
    feeder_lockout_minutes: Number($("lockoutMinutes").value),
    schedule_enabled: $("scheduleEnabled").checked,
    schedule_days: [...selectedDays].sort(),
    feeder_time: $("feederTime").value,
    light_on_time: $("lightOnTime").value,
    light_off_time: $("lightOffTime").value,
  };
  try {
    await api("/api/settings", {method:"POST", body:JSON.stringify(body)});
    settingsDirty = false;
    showMessage("Schedule saved.");
    await refreshStatus();
    await refreshEvents();
  } catch(e) { showMessage(e.message, true); }
};

$("refreshDevices").onclick = async () => {
  await refreshDevices();
  await refreshStatus();
};

$("deviceSelect").onchange = async (e) => {
  if (!e.target.value) return;
  try {
    await api("/api/device", {method:"POST", body:JSON.stringify({device_id:e.target.value})});
    showMessage("Wemo selected.");
    await refreshStatus();
  } catch(err) { showMessage(err.message, true); }
};

function wireSettingsDirtyTracking() {
  if (settingsWired) return;
  settingsWired = true;
  ["scheduleEnabled","feederTime","pulseSeconds","lockoutMinutes","lightOnTime","lightOffTime"].forEach(id => {
    const el = $(id);
    if (!el) return;
    el.addEventListener("input", () => { settingsDirty = true; });
    el.addEventListener("change", () => { settingsDirty = true; });
  });
}

$("bridgeUrl").value = currentBridgeUrl();
$("lastCommand").textContent = localStorage.getItem("wemoteLastCommand") || "None yet";
refreshRemoteBadge();
wireSettingsDirtyTracking();
renderDays();
refreshStatus();
refreshDevices();
refreshEvents();
tickClock();
setInterval(tickClock, 250);
setInterval(refreshStatus, 5000);
setInterval(refreshEvents, 30000);
if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("/sw.js").catch(()=>{});
