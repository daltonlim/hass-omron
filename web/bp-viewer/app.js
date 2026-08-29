let session = null;
let readings = [];
const expandedRows = new Set();
const diagnostics = { rssi: null, pollSeconds: null, connected: false };
const STORAGE_KEY = "omron-bp-viewer";

const modelSelect = document.getElementById("model");
const statusEl = document.getElementById("bleStatus");
const logEl = document.getElementById("log");
const btnConnect = document.getElementById("btnConnect");
const btnDisconnect = document.getElementById("btnDisconnect");
const btnTime = document.getElementById("btnTime");

for (const [id, profile] of Object.entries(PROFILES)) {
  const opt = document.createElement("option");
  opt.value = id;
  opt.textContent = profile.label;
  if (id === "U705T") opt.selected = true;
  modelSelect.appendChild(opt);
}

function log(line) {
  const stamp = new Date().toLocaleTimeString();
  logEl.textContent += `\n${stamp} ${line}`;
  logEl.scrollTop = logEl.scrollHeight;
}

function setStatus(text, kind) {
  statusEl.textContent = text;
  statusEl.className = `status ${kind || ""}`;
}

function flags(rec) {
  const bits = [];
  if (rec.mov) bits.push("movement");
  if (rec.ihb) bits.push("irregular");
  if (rec.cuff) bits.push("cuff");
  if (rec.battery) bits.push("battery");
  return bits.join(", ") || "—";
}

function rateReading(rec) {
  const sys = rec.sys;
  const dia = rec.dia;
  let category = "Normal";
  let tone = "normal";
  if (sys > 180 || dia > 120) {
    category = "Hypertensive crisis";
    tone = "crisis";
  } else if (sys >= 140 || dia >= 90) {
    category = "Hypertension stage 2";
    tone = "stage2";
  } else if (sys >= 130 || dia >= 80) {
    category = "Hypertension stage 1";
    tone = "stage1";
  } else if (sys >= 120 && dia < 80) {
    category = "Elevated";
    tone = "elevated";
  }
  const rating = category === "Normal" ? "Good" : "Bad";
  return { category, rating, tone };
}

function lozenge(recRate, large) {
  const label = recRate.rating === "Good" ? "Good · Normal" : `Bad · ${recRate.category}`;
  const size = large ? " lozenge-lg" : "";
  return `<span class="lozenge ${recRate.tone}${size}" title="${recRate.category}">${label}</span>`;
}

function round(value, digits) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/** ACC/AHA 2017 thresholds, worded to match the Home Assistant category sensor. */
function categoryLabel(sys, dia) {
  if (sys > 180 || dia > 120) return "Hypertensive Crisis";
  if (sys >= 140 || dia >= 90) return "Hypertension Stage 2";
  if (sys >= 130 || dia >= 80) return "Hypertension Stage 1";
  if (sys >= 120 && dia < 80) return "Elevated";
  return "Normal";
}

function entitySlug(rec) {
  const model = (modelSelect.value || "omron").toLowerCase().replace(/[^a-z0-9]+/g, "_");
  return `${model}_user_${rec.user}`;
}

/** Derived metrics, rounded the same way the Home Assistant parser rounds them. */
function derivedMetrics(rec) {
  const pulsePressure = rec.sys - rec.dia;
  return {
    pulsePressure: round(pulsePressure, 1),
    estimatedMap: round(rec.dia + pulsePressure / 3, 1),
    shockIndex: rec.sys > 0 ? round(rec.bpm / rec.sys, 2) : null,
    ratePressureProduct: round(rec.sys * rec.bpm, 1),
    category: categoryLabel(rec.sys, rec.dia),
  };
}

function measurementEntities(rec) {
  const derived = derivedMetrics(rec);
  return [
    { name: "Systolic", key: "blood_pressure_systolic", state: rec.sys, unit: "mmHg" },
    { name: "Diastolic", key: "blood_pressure_diastolic", state: rec.dia, unit: "mmHg" },
    { name: "Pulse", key: "heart_rate", state: rec.bpm, unit: "bpm" },
    { name: "Pulse Pressure", key: "pulse_pressure", state: derived.pulsePressure, unit: "mmHg" },
    { name: "Estimated MAP", key: "mean_arterial_pressure_estimated", state: derived.estimatedMap, unit: "mmHg" },
    { name: "Shock Index", key: "shock_index", state: derived.shockIndex, unit: "ratio" },
    { name: "Rate Pressure Product", key: "rate_pressure_product", state: derived.ratePressureProduct, unit: "mmHg*bpm" },
    { name: "BP Category (ACC/AHA)", key: "blood_pressure_category", state: derived.category },
    {
      name: "Measured At",
      key: "measurement_timestamp",
      state: rec.datetime ? rec.datetime.toLocaleString() : null,
    },
  ];
}

function statusEntities(rec) {
  return [
    { name: "Cuff Fit", key: "cuff_fit", on: Boolean(rec.cuff), hint: "On means the cuff was not wrapped correctly." },
    { name: "Body Movement", key: "body_movement", on: Boolean(rec.mov), hint: "On means movement was detected during the measurement." },
    { name: "Irregular Pulse", key: "irregular_pulse", on: Boolean(rec.ihb), hint: "On means an irregular heart rhythm was detected." },
    {
      name: "Improper Position",
      key: "improper_position",
      on: rec.pos == null ? null : Boolean(rec.pos),
      hint: "On means the device was not at heart level. Only wrist models report this.",
    },
    {
      name: "Battery",
      key: "battery",
      on: Boolean(rec.battery),
      hint: "On means the batteries should be replaced.",
      diagnostic: true,
    },
  ];
}

function diagnosticEntities() {
  return [
    {
      name: "Signal Strength",
      key: "signal_strength",
      state: diagnostics.rssi,
      unit: "dBm",
      hint: "Chrome only reports advertisement RSSI with experimental web platform features enabled.",
      diagnostic: true,
    },
    {
      name: "Duration",
      key: "duration",
      state: diagnostics.pollSeconds == null ? null : round(diagnostics.pollSeconds, 2),
      unit: "s",
      hint: "Wall-clock seconds for the last download.",
      diagnostic: true,
    },
    {
      name: "Connection",
      key: "connection",
      on: diagnostics.connected,
      hint: "On while this page is actively communicating with the monitor.",
      diagnostic: true,
    },
  ];
}

function entityCard(entity, slug) {
  const isBinary = "on" in entity;
  const domain = isBinary ? "binary_sensor" : "sensor";
  let stateHtml;
  if (isBinary) {
    if (entity.on == null) stateHtml = `<span class="pill unknown">unknown</span>`;
    else stateHtml = `<span class="pill ${entity.on ? "on" : "off"}">${entity.on ? "On" : "Off"}</span>`;
  } else if (entity.state == null || entity.state === "") {
    stateHtml = `<span class="pill unknown">unknown</span>`;
  } else {
    const unit = entity.unit ? ` <span class="unit">${entity.unit}</span>` : "";
    stateHtml = `<span class="entity-value">${entity.state}</span>${unit}`;
  }
  const badge = entity.diagnostic ? `<span class="badge diag">diagnostic</span>` : "";
  const hint = entity.hint ? `<div class="entity-hint">${entity.hint}</div>` : "";
  return `<div class="entity">
    <div class="entity-head"><span class="entity-name">${entity.name}</span>${badge}</div>
    <div class="entity-state">${stateHtml}</div>
    <div class="entity-id">${domain}.${slug}_${entity.key}</div>
    ${hint}
  </div>`;
}

function entityGroup(title, note, entities, slug) {
  const cards = entities.map((entity) => entityCard(entity, slug)).join("");
  return `<section class="entity-group">
    <h3>${title}</h3>
    <p class="entity-note">${note}</p>
    <div class="entity-grid">${cards}</div>
  </section>`;
}

function detailPanel(rec) {
  const slug = entitySlug(rec);
  return `<div class="entity-panel">
    ${entityGroup("Sensors", "Values Home Assistant publishes for this measurement.", measurementEntities(rec), slug)}
    ${entityGroup("Status flags", "Binary sensors carried by this measurement.", statusEntities(rec), slug)}
    ${entityGroup("Device diagnostics", "Shared across the device, shown from the latest download.", diagnosticEntities(), slug)}
  </div>`;
}

function readingKey(rec) {
  return `${rec.user}-${rec.slot}-${rec.datetime ? rec.datetime.getTime() : "na"}`;
}

const readingsByKey = new Map();

function toggleRow(key) {
  const rec = readingsByKey.get(key);
  const row = document.querySelector(`tr.reading-row[data-key="${key}"]`);
  const detail = document.querySelector(`tr.detail-row[data-detail="${key}"]`);
  if (!rec || !row || !detail) return;
  const open = !expandedRows.has(key);
  if (open) expandedRows.add(key);
  else expandedRows.delete(key);
  row.classList.toggle("open", open);
  row.setAttribute("aria-expanded", String(open));
  row.querySelector(".caret").textContent = open ? "▾" : "▸";
  detail.classList.toggle("hidden", !open);
  detail.firstElementChild.innerHTML = open ? detailPanel(rec) : "";
}

function refreshOpenPanels() {
  for (const key of expandedRows) {
    const rec = readingsByKey.get(key);
    const detail = document.querySelector(`tr.detail-row[data-detail="${key}"]`);
    if (rec && detail) detail.firstElementChild.innerHTML = detailPanel(rec);
  }
}

function render() {
  const latest = readings[0];
  document.getElementById("statSys").textContent = latest ? `${latest.sys}` : "—";
  document.getElementById("statDia").textContent = latest ? `${latest.dia}` : "—";
  document.getElementById("statPulse").textContent = latest ? `${latest.bpm}` : "—";
  document.getElementById("statCount").textContent = String(readings.length);
  const rated = readings.map((r) => ({ ...r, ...rateReading(r) }));
  const good = rated.filter((r) => r.rating === "Good").length;
  const bad = rated.length - good;
  const latestRate = latest ? rateReading(latest) : null;
  const ratingEl = document.getElementById("statRating");
  if (latestRate) {
    ratingEl.innerHTML = lozenge(latestRate, true);
  } else {
    ratingEl.textContent = "—";
  }
  document.getElementById("statSplit").textContent = rated.length ? `${good} / ${bad}` : "—";
  const tbody = document.getElementById("rows");
  if (!readings.length) {
    tbody.innerHTML = `<tr><td class="empty" colspan="8">No stored measurements found.</td></tr>`;
  } else {
    readingsByKey.clear();
    tbody.innerHTML = rated
      .map((r) => {
        const key = readingKey(r);
        readingsByKey.set(key, r);
        const open = expandedRows.has(key);
        return `<tr class="reading-row row-${r.rating.toLowerCase()}${open ? " open" : ""}" data-key="${key}" tabindex="0" role="button" aria-expanded="${open}">
        <td class="caret-cell"><span class="caret">${open ? "▾" : "▸"}</span></td>
        <td>${r.datetime ? r.datetime.toLocaleString() : "—"}</td>
        <td>${r.user}</td>
        <td>${r.sys}</td>
        <td>${r.dia}</td>
        <td>${r.bpm}</td>
        <td>${lozenge(r)}</td>
        <td>${flags(r)}</td>
      </tr>
      <tr class="detail-row${open ? "" : " hidden"}" data-detail="${key}">
        <td colspan="8">${open ? detailPanel(r) : ""}</td>
      </tr>`;
      })
      .join("");
  }
  for (const key of expandedRows) {
    if (!readingsByKey.has(key)) expandedRows.delete(key);
  }
  drawChart(readings);
  drawGuideChart(readings);
}

function readingIdentity(rec) {
  return [
    rec.user,
    rec.slot,
    rec.datetime ? rec.datetime.toISOString() : "na",
    rec.sys,
    rec.dia,
    rec.bpm,
  ].join("|");
}

function sortReadings(rows) {
  rows.sort((a, b) => {
    const ta = a.datetime ? a.datetime.getTime() : 0;
    const tb = b.datetime ? b.datetime.getTime() : 0;
    return tb - ta;
  });
  return rows;
}

function mergeReadings(incoming) {
  const byId = new Map();
  for (const rec of readings) byId.set(readingIdentity(rec), rec);
  for (const rec of incoming) byId.set(readingIdentity(rec), rec);
  readings = sortReadings([...byId.values()]);
}

function serializeReading(rec) {
  return {
    user: rec.user,
    slot: rec.slot,
    sys: rec.sys,
    dia: rec.dia,
    bpm: rec.bpm,
    ihb: rec.ihb || 0,
    mov: rec.mov || 0,
    cuff: rec.cuff || 0,
    battery: rec.battery || 0,
    pos: rec.pos == null ? null : rec.pos,
    datetime: rec.datetime ? rec.datetime.toISOString() : null,
  };
}

function reviveReading(rec) {
  return {
    ...rec,
    datetime: rec.datetime ? new Date(rec.datetime) : null,
  };
}

function persist() {
  const payload = {
    version: 1,
    savedAt: new Date().toISOString(),
    model: modelSelect.value,
    diagnostics: {
      rssi: diagnostics.rssi,
      pollSeconds: diagnostics.pollSeconds,
    },
    readings: readings.map(serializeReading),
  };
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
  } catch (err) {
    log(`Could not save readings (${err.message})`);
  }
}

function restore() {
  let raw;
  try {
    raw = localStorage.getItem(STORAGE_KEY);
  } catch {
    return false;
  }
  if (!raw) return false;
  try {
    const payload = JSON.parse(raw);
    if (!payload || !Array.isArray(payload.readings)) return false;
    if (payload.model && PROFILES[payload.model]) modelSelect.value = payload.model;
    if (payload.diagnostics) {
      diagnostics.rssi = payload.diagnostics.rssi ?? null;
      diagnostics.pollSeconds = payload.diagnostics.pollSeconds ?? null;
    }
    readings = sortReadings(payload.readings.map(reviveReading));
    return readings.length > 0;
  } catch (err) {
    log(`Could not restore saved readings (${err.message})`);
    return false;
  }
}

function clearSaved() {
  readings = [];
  expandedRows.clear();
  readingsByKey.clear();
  diagnostics.rssi = null;
  diagnostics.pollSeconds = null;
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* ignore quota / private mode */
  }
  render();
}

const rowsBody = document.getElementById("rows");

rowsBody.addEventListener("click", (event) => {
  const row = event.target.closest("tr.reading-row");
  if (row) toggleRow(row.dataset.key);
});

rowsBody.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const row = event.target.closest("tr.reading-row");
  if (!row) return;
  event.preventDefault();
  toggleRow(row.dataset.key);
});

const ZONE_COLORS = {
  normal: "#1b6b66",
  elevated: "#c9a227",
  stage1: "#d97706",
  stage2: "#b42318",
  crisis: "#6b0f0f",
};

function toneAt(sys, dia) {
  return rateReading({ sys, dia }).tone;
}

function drawChart(rows) {
  const canvas = document.getElementById("chart");
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#fffaf2";
  ctx.fillRect(0, 0, w, h);
  const chronological = [...rows].reverse();
  const ys = chronological.map((r) => r.sys);
  const yd = chronological.map((r) => r.dia);
  const yp = chronological.map((r) => r.bpm);
  const min = Math.min(40, ...(ys.length ? ys : [40]), ...(yd.length ? yd : [40]), ...(yp.length ? yp : [40]));
  const max = Math.max(180, ...(ys.length ? ys : [180]), ...(yd.length ? yd : [80]), ...(yp.length ? yp : [80]));
  const padL = 42;
  const padR = 16;
  const padT = 16;
  const padB = 28;
  const yAt = (v) => padT + ((max - v) / (max - min)) * (h - padT - padB);
  const xAt = (i) => padL + (i * (w - padL - padR)) / Math.max(chronological.length - 1, 1);

  const guides = [
    { v: 80, label: "dia 80", color: "#1b6b66" },
    { v: 120, label: "sys 120", color: "#1b6b66" },
    { v: 130, label: "130", color: "#d97706" },
    { v: 140, label: "140", color: "#b42318" },
    { v: 180, label: "180", color: "#6b0f0f" },
  ];
  ctx.setLineDash([5, 4]);
  ctx.font = "11px ui-sans-serif, sans-serif";
  for (const g of guides) {
    if (g.v < min || g.v > max) continue;
    const y = yAt(g.v);
    ctx.strokeStyle = g.color;
    ctx.globalAlpha = 0.45;
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(w - padR, y);
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.fillStyle = g.color;
    ctx.fillText(g.label, 4, y + 4);
  }
  ctx.setLineDash([]);

  ctx.strokeStyle = "#d9d0c2";
  ctx.beginPath();
  ctx.moveTo(padL, padT);
  ctx.lineTo(padL, h - padB);
  ctx.lineTo(w - padR, h - padB);
  ctx.stroke();

  if (!chronological.length) {
    ctx.fillStyle = "#5c6774";
    ctx.fillText("Connect to plot readings against 120/80.", padL + 8, h / 2);
    return;
  }

  const series = [
    { values: ys, color: "#b42318" },
    { values: yd, color: "#1b6b66" },
    { values: yp, color: "#8a5a12" },
  ];
  for (const s of series) {
    ctx.strokeStyle = s.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    s.values.forEach((v, i) => {
      const x = xAt(i);
      const y = yAt(v);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }
}

function drawGuideChart(rows) {
  const canvas = document.getElementById("guide");
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#fffaf2";
  ctx.fillRect(0, 0, w, h);

  const diaMin = 40;
  const diaMax = 130;
  const sysMin = 70;
  const sysMax = 200;
  const padL = 40;
  const padR = 12;
  const padT = 12;
  const padB = 32;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;
  const xAt = (dia) => padL + ((dia - diaMin) / (diaMax - diaMin)) * plotW;
  const yAt = (sys) => padT + ((sysMax - sys) / (sysMax - sysMin)) * plotH;

  ctx.save();
  ctx.beginPath();
  ctx.rect(padL, padT, plotW, plotH);
  ctx.clip();

  const step = 2;
  for (let dia = diaMin; dia < diaMax; dia += step) {
    for (let sys = sysMin; sys < sysMax; sys += step) {
      const tone = toneAt(sys + step / 2, dia + step / 2);
      ctx.fillStyle = ZONE_COLORS[tone];
      ctx.globalAlpha = 0.28;
      const x = xAt(dia);
      const y = yAt(sys + step);
      ctx.fillRect(x, y, Math.ceil(xAt(dia + step) - x), Math.ceil(yAt(sys) - y));
    }
  }
  ctx.globalAlpha = 1;
  ctx.restore();

  ctx.setLineDash([4, 3]);
  ctx.strokeStyle = "#1a222c";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(xAt(80), yAt(sysMin));
  ctx.lineTo(xAt(80), yAt(sysMax));
  ctx.moveTo(xAt(diaMin), yAt(120));
  ctx.lineTo(xAt(diaMax), yAt(120));
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = "#1a222c";
  ctx.font = "11px ui-sans-serif, sans-serif";
  ctx.fillText("80", xAt(80) - 8, h - 8);
  ctx.fillText("120", 6, yAt(120) + 4);
  ctx.fillText("Diastolic", w / 2 - 24, h - 6);
  ctx.save();
  ctx.translate(12, h / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText("Systolic", 0, 0);
  ctx.restore();

  ctx.strokeStyle = "#d9d0c2";
  ctx.strokeRect(padL, padT, plotW, plotH);

  rows.forEach((r, i) => {
    const x = xAt(Math.min(diaMax, Math.max(diaMin, r.dia)));
    const y = yAt(Math.min(sysMax, Math.max(sysMin, r.sys)));
    const latest = i === 0;
    ctx.beginPath();
    ctx.arc(x, y, latest ? 6 : 4, 0, Math.PI * 2);
    ctx.fillStyle = latest ? "#1a222c" : "#4a5560";
    ctx.fill();
    ctx.strokeStyle = "#fffaf2";
    ctx.lineWidth = 1.5;
    ctx.stroke();
  });
}

function download(name, text, type) {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

btnConnect.addEventListener("click", async () => {
  if (!window.isSecureContext) {
    setStatus("Open this page via http://127.0.0.1:8765 — not as a file.", "error");
    return;
  }
  btnConnect.disabled = true;
  setStatus("Connecting…");
  try {
    session = new OmronBleSession(PROFILES[modelSelect.value], log);
    await session.connect();
    diagnostics.connected = true;
    setStatus("Downloading stored readings…");
    const incoming = await session.pullReadings();
    diagnostics.rssi = session.rssi;
    diagnostics.pollSeconds = session.lastPollSeconds;
    diagnostics.connected = session.connected;
    mergeReadings(incoming);
    persist();
    render();
    setStatus(`Downloaded ${incoming.length} reading(s). ${readings.length} saved.`, "ok");
    btnDisconnect.disabled = false;
    btnTime.disabled = false;
  } catch (err) {
    diagnostics.connected = Boolean(session?.connected);
    diagnostics.pollSeconds = session?.lastPollSeconds ?? diagnostics.pollSeconds;
    refreshOpenPanels();
    log(String(err && err.message ? err.message : err));
    setStatus(err.message || String(err), "error");
    btnConnect.disabled = false;
  }
});

btnDisconnect.addEventListener("click", async () => {
  if (session) await session.disconnect();
  session = null;
  diagnostics.connected = false;
  refreshOpenPanels();
  btnConnect.disabled = false;
  btnDisconnect.disabled = true;
  btnTime.disabled = true;
  setStatus("Disconnected.");
});

btnTime.addEventListener("click", async () => {
  if (!session) return;
  btnTime.disabled = true;
  setStatus("Writing computer time to the cuff…");
  try {
    const result = await session.syncTime();
    const parts = [];
    if (result.eeprom) parts.push("EEPROM");
    if (result.cts) parts.push("CTS");
    setStatus(`Clock updated (${parts.join(" + ") || "no-op"}).`, "ok");
  } catch (err) {
    log(String(err && err.message ? err.message : err));
    setStatus(err.message || String(err), "error");
  } finally {
    btnTime.disabled = false;
  }
});

/** One flat row per reading, carrying every stat the entity panel shows. */
function exportRow(rec) {
  const derived = derivedMetrics(rec);
  const { rating } = rateReading(rec);
  return {
    time: rec.datetime ? rec.datetime.toISOString() : "",
    time_local: rec.datetime ? rec.datetime.toLocaleString() : "",
    user: rec.user,
    slot: rec.slot,
    systolic_mmhg: rec.sys,
    diastolic_mmhg: rec.dia,
    pulse_bpm: rec.bpm,
    pulse_pressure_mmhg: derived.pulsePressure,
    estimated_map_mmhg: derived.estimatedMap,
    shock_index_ratio: derived.shockIndex,
    rate_pressure_product_mmhg_bpm: derived.ratePressureProduct,
    bp_category: derived.category,
    rating,
    cuff_fit: rec.cuff ? 1 : 0,
    body_movement: rec.mov ? 1 : 0,
    irregular_pulse: rec.ihb ? 1 : 0,
    improper_position: rec.pos == null ? "" : rec.pos ? 1 : 0,
    battery: rec.battery ? 1 : 0,
    rssi_dbm: diagnostics.rssi == null ? "" : diagnostics.rssi,
    poll_duration_s: diagnostics.pollSeconds == null ? "" : round(diagnostics.pollSeconds, 2),
    connection: diagnostics.connected ? 1 : 0,
  };
}

function csvCell(value) {
  const text = value == null ? "" : String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

const EXPORT_TEMPLATE = { user: "", slot: "", sys: 0, dia: 0, bpm: 0 };

document.getElementById("btnCsv").addEventListener("click", () => {
  const columns = Object.keys(exportRow(readings[0] ?? EXPORT_TEMPLATE));
  const lines = readings.map((rec) => {
    const row = exportRow(rec);
    return columns.map((column) => csvCell(row[column])).join(",");
  });
  download("omron-readings.csv", [columns.join(","), ...lines].join("\n"), "text/csv");
});

document.getElementById("btnJson").addEventListener("click", () => {
  download(
    "omron-readings.json",
    JSON.stringify(readings.map(exportRow), null, 2),
    "application/json"
  );
});

document.getElementById("btnClear").addEventListener("click", () => {
  if (!readings.length) {
    setStatus("Nothing saved yet.");
    return;
  }
  if (!window.confirm(`Clear ${readings.length} saved reading(s) from this browser?`)) return;
  clearSaved();
  setStatus("Saved readings cleared.");
});

if (restore()) {
  render();
  setStatus(`Restored ${readings.length} saved reading(s).`, "ok");
} else {
  drawChart([]);
  drawGuideChart([]);
}
