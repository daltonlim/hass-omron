const SVC_FE4A = "0000fe4a-0000-1000-8000-00805f9b34fb";
const SVC_CLASSIC = "ecbe3980-c9a2-11e1-b1bd-0002a5d5c51b";
const SVC_DIS = "0000180a-0000-1000-8000-00805f9b34fb";
const SVC_CTS = "00001805-0000-1000-8000-00805f9b34fb";
const CHAR_CTS = "00002a2b-0000-1000-8000-00805f9b34fb";
const CHAR_LTI = "00002a0f-0000-1000-8000-00805f9b34fb";
const CHAR_MODEL = "00002a24-0000-1000-8000-00805f9b34fb";
const CHAR_UNLOCK = "b305b680-aee7-11e1-a730-0002a5d5c51b";
const CHAR_RX0 = "49123040-aee8-11e1-a74d-0002a5d5c51b";
const CHAR_TX0 = "db5b55e0-aee7-11e1-965e-0002a5d5c51b";
const CLASSIC_RX = [
  CHAR_RX0,
  "4d0bf320-aee8-11e1-a0d9-0002a5d5c51b",
  "5128ce60-aee8-11e1-b84b-0002a5d5c51b",
  "560f1420-aee8-11e1-8184-0002a5d5c51b",
];
const CLASSIC_TX = [
  CHAR_TX0,
  "e0b8a060-aee7-11e1-92f4-0002a5d5c51b",
  "0ae12b00-aee8-11e1-a192-0002a5d5c51b",
  "10e1ba60-aee8-11e1-89e5-0002a5d5c51b",
];
const PAIRING_KEY = hexToBytes("deadbeaf12341234deadbeaf12341234");

const PROFILES = {
  U705T: {
    label: "U705T / HEM-7142T2 (modern)",
    parent: SVC_FE4A,
    rx: [CHAR_RX0],
    tx: [CHAR_TX0],
    unlock: CHAR_UNLOCK,
    unlockMode: "token",
    endianness: "little",
    userStart: [0x02e8],
    recordCount: [14],
    recordSize: 0x0e,
    blockSize: 0x2c,
    parser: "vital14",
    settingsRead: 0x0260,
    settingsWrite: 0x02a4,
    timeSync: [0x2c, 0x3c],
    timeLayout: "modern_offset8",
  },
  "HEM-7142T2": {
    label: "HEM-7142T2",
    parent: SVC_FE4A,
    rx: [CHAR_RX0],
    tx: [CHAR_TX0],
    unlock: CHAR_UNLOCK,
    unlockMode: "token",
    endianness: "little",
    userStart: [0x02e8],
    recordCount: [14],
    recordSize: 0x0e,
    blockSize: 0x2c,
    parser: "vital14",
    settingsRead: 0x0260,
    settingsWrite: 0x02a4,
    timeSync: [0x2c, 0x3c],
    timeLayout: "modern_offset8",
  },
  "HEM-7146T": {
    label: "HEM-7146T / X2 Smart+",
    parent: SVC_FE4A,
    rx: [CHAR_RX0],
    tx: [CHAR_TX0],
    unlock: CHAR_UNLOCK,
    unlockMode: "token",
    endianness: "little",
    userStart: [0x02e8],
    recordCount: [30],
    recordSize: 0x0e,
    blockSize: 0x2c,
    parser: "vital14",
    settingsRead: 0x0260,
    settingsWrite: 0x02a4,
    timeSync: [0x2c, 0x3c],
    timeLayout: "modern_offset8",
  },
  "HEM-7600T": {
    label: "HEM-7600T / EVOLV (classic key)",
    parent: SVC_CLASSIC,
    rx: CLASSIC_RX,
    tx: CLASSIC_TX,
    unlock: CHAR_UNLOCK,
    unlockMode: "classic",
    endianness: "big",
    userStart: [0x02ac],
    recordCount: [100],
    recordSize: 0x0e,
    blockSize: 0x2c,
    parser: "vital14bit",
    settingsRead: 0x0260,
    settingsWrite: 0x0286,
    timeSync: [0x14, 0x1e],
    timeLayout: "classic_mixed",
  },
};

function hexToBytes(hex) {
  const clean = hex.replace(/[^0-9a-f]/gi, "");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function xorCrc(bytes) {
  let crc = 0;
  for (const b of bytes) crc ^= b;
  return crc;
}

function withXor(bytes) {
  const out = new Uint8Array(bytes.length + 1);
  out.set(bytes);
  out[bytes.length] = xorCrc(bytes);
  return out;
}

function parseVital14(data) {
  if (data.length < 8) throw new Error("short record");
  const rawSys = data[0];
  if (rawSys > 0xe1) throw new Error("empty");
  const flags1 = data[4] | (data[5] << 8);
  const flags2 = data[6] | (data[7] << 8);
  if (data[1] === 0 && data[2] === 0 && (data[3] & 0x3f) === 0 && flags1 === 0 && flags2 === 0) {
    throw new Error("empty");
  }
  const year = 2000 + (data[3] & 0x3f);
  const hour = flags1 & 0x1f;
  const day = (flags1 >> 5) & 0x1f;
  const month = (flags1 >> 10) & 0x0f;
  const second = Math.min(flags2 & 0x3f, 59);
  const minute = Math.min((flags2 >> 6) & 0x3f, 59);
  let datetime = null;
  try {
    datetime = new Date(year, month - 1, day, hour, minute, second);
    if (Number.isNaN(datetime.getTime())) datetime = null;
  } catch {
    datetime = null;
  }
  return {
    sys: rawSys + 25,
    dia: data[1],
    bpm: data[2],
    ihb: (flags1 >> 14) & 1,
    mov: (flags1 >> 15) & 1,
    cuff: (flags2 >> 12) & 1,
    battery: (flags2 >> 13) & 1,
    datetime,
  };
}

function bitsToInt(data, firstBit, lastBit) {
  let big = 0n;
  for (const b of data) big = (big << 8n) + BigInt(b);
  const numBits = BigInt(lastBit - firstBit + 1);
  const shift = BigInt(data.length * 8 - (lastBit + 1));
  const mask = (1n << numBits) - 1n;
  return Number((big >> shift) & mask);
}

function parseVital14Bit(data) {
  const dia = bitsToInt(data, 0, 7);
  const sys = bitsToInt(data, 8, 15) + 25;
  const year = bitsToInt(data, 16, 23) + 2000;
  const bpm = bitsToInt(data, 24, 31);
  const month = bitsToInt(data, 34, 37);
  const day = bitsToInt(data, 38, 42);
  const hour = bitsToInt(data, 43, 47);
  const minute = bitsToInt(data, 52, 57);
  const second = Math.min(bitsToInt(data, 58, 63), 59);
  let datetime = null;
  try {
    datetime = new Date(year, month - 1, day, hour, minute, second);
    if (Number.isNaN(datetime.getTime())) datetime = null;
  } catch {
    datetime = null;
  }
  return {
    sys,
    dia,
    bpm,
    mov: bitsToInt(data, 32, 32),
    ihb: bitsToInt(data, 33, 33),
    cuff: bitsToInt(data, 51, 51),
    battery: bitsToInt(data, 50, 50),
    datetime,
  };
}

function plausible(rec) {
  return rec.sys >= 60 && rec.sys <= 260 && rec.dia >= 30 && rec.dia <= 180 && rec.bpm >= 30 && rec.bpm <= 220;
}

class OmronBleSession {
  constructor(profile, log) {
    this.profile = profile;
    this.log = log || (() => {});
    this.device = null;
    this.server = null;
    this.rxChars = [];
    this.txChars = [];
    this.unlockChar = null;
    this.fragments = [null, null, null, null];
    this.pending = null;
    this.single = profile.tx.length === 1;
    this.memoryOpen = false;
    this.rssi = null;
    this.lastPollSeconds = null;
    this.rssiAbort = null;
  }

  get connected() {
    return Boolean(this.server?.connected);
  }

  /**
   * Advertisement RSSI is only exposed behind chrome://flags/#enable-experimental-web-platform-features
   * on desktop, so treat a missing value as "unknown" rather than an error.
   */
  async watchRssi() {
    if (typeof this.device?.watchAdvertisements !== "function") return;
    try {
      this.rssiAbort = new AbortController();
      this.device.addEventListener("advertisementreceived", (event) => {
        if (typeof event.rssi === "number") this.rssi = event.rssi;
      });
      await this.device.watchAdvertisements({ signal: this.rssiAbort.signal });
    } catch {
      this.rssiAbort = null;
    }
  }

  async connect() {
    if (!navigator.bluetooth) {
      throw new Error("Web Bluetooth is not available. Use Chrome on desktop or Android.");
    }
    this.log("Requesting Bluetooth device…");
    try {
      this.device = await navigator.bluetooth.requestDevice({
        filters: [
          { services: [SVC_FE4A] },
          { services: [SVC_CLASSIC] },
          { namePrefix: "BLESmart_" },
          { namePrefix: "BLEsmart_" },
          { namePrefix: "HEM-" },
          { manufacturerData: [{ companyIdentifier: 0x020e }] },
        ],
        optionalServices: [SVC_FE4A, SVC_CLASSIC, SVC_DIS, SVC_CTS],
      });
    } catch (err) {
      this.log(`Filtered scan failed (${err.message}); showing all Bluetooth devices`);
      this.device = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: [SVC_FE4A, SVC_CLASSIC, SVC_DIS, SVC_CTS],
      });
    }
    this.device.addEventListener("gattserverdisconnected", () => this.log("Disconnected"));
    await this.watchRssi();
    this.log(`Connecting to ${this.device.name || "Omron"}…`);
    this.server = await this.device.gatt.connect();
    await delay(1200);
    const parent = await this.server.getPrimaryService(this.profile.parent);
    this.rxChars = [];
    this.txChars = [];
    for (const uuid of this.profile.rx) {
      this.rxChars.push(await parent.getCharacteristic(uuid));
    }
    for (const uuid of this.profile.tx) {
      this.txChars.push(await parent.getCharacteristic(uuid));
    }
    this.unlockChar = await parent.getCharacteristic(this.profile.unlock);
    this.log("GATT ready. Unlocking…");
    await this.unlock();
    this.log("Opening memory session…");
    await this.subscribeRx();
    await delay(750);
    const start = hexToBytes("0800000000100018");
    const reply = await this.command(start, "8000");
    if (reply.payload[0]) {
      throw new Error(`Device rejected memory session (0x${reply.payload[0].toString(16)})`);
    }
    this.memoryOpen = true;
  }

  async disconnect() {
    try {
      this.rssiAbort?.abort();
      this.rssiAbort = null;
      if (this.server?.connected) {
        try {
          await this.command(hexToBytes("080f000000000007"), "8f00");
        } catch {
          /* ignore close errors */
        }
        this.device.gatt.disconnect();
      }
    } finally {
      this.server = null;
    }
  }

  async unlock() {
    if (this.profile.unlockMode === "token") {
      await this.tokenUnlock();
      return;
    }
    await this.classicUnlock();
  }

  async tokenUnlock() {
    const token = crypto.getRandomValues(new Uint8Array(4));
    const packet = new Uint8Array(20);
    packet[0] = 0x11;
    packet.set(token, 1);
    await this.unlockChar.startNotifications();
    try {
      try {
        await this.rxChars[0].startNotifications();
      } catch {
        /* already enabled */
      }
      await delay(750);
      try {
        await this._tokenWrite(packet, token, false);
      } catch {
        this.log("Token write-without-response timed out; retrying with response");
        await this._tokenWrite(packet, token, true);
      }
    } finally {
      try {
        await this.unlockChar.stopNotifications();
      } catch {
        /* ignore */
      }
      try {
        await this.rxChars[0].stopNotifications();
      } catch {
        /* ignore */
      }
    }
    this.log(`Token unlock OK (${bytesToHex(token)})`);
  }

  async _tokenWrite(packet, token, withResponse) {
    const ack = waitFor(
      (data) =>
        data.length >= 6 &&
        data[0] === 0x91 &&
        data[1] === 0x00 &&
        bytesToHex(data.slice(2, 6)) === bytesToHex(token),
      5000
    );
    this.unlockChar.addEventListener("characteristicvaluechanged", ack.listener);
    try {
      await writeChar(this.unlockChar, packet, withResponse);
      await ack.promise;
    } finally {
      this.unlockChar.removeEventListener("characteristicvaluechanged", ack.listener);
    }
  }

  async classicUnlock() {
    const packet = new Uint8Array(1 + PAIRING_KEY.length);
    packet[0] = 0x01;
    packet.set(PAIRING_KEY, 1);
    const ack = waitFor((data) => data.length >= 1 && data[0] === 0x81, 5000);
    await this.unlockChar.startNotifications();
    this.unlockChar.addEventListener("characteristicvaluechanged", ack.listener);
    await delay(750);
    await writeChar(this.unlockChar, packet, true);
    await ack.promise;
    this.unlockChar.removeEventListener("characteristicvaluechanged", ack.listener);
    try {
      await this.unlockChar.stopNotifications();
    } catch {
      /* ignore */
    }
    this.log("Classic pairing-key unlock OK");
  }

  async subscribeRx() {
    for (const ch of this.rxChars) {
      ch.addEventListener("characteristicvaluechanged", (ev) => {
        const bytes = new Uint8Array(ev.target.value.buffer);
        this.onRx(ch, bytes);
      });
      try {
        await ch.startNotifications();
      } catch {
        /* already enabled from token unlock */
      }
    }
  }

  onRx(char, bytes) {
    const idx = this.rxChars.findIndex((c) => c.uuid === char.uuid);
    const channel = idx < 0 ? 0 : idx;
    if (channel === 0) this.fragments = [null, null, null, null];
    this.fragments[channel] = bytes;
    if (!this.fragments[0]) return;
    let frame;
    if (this.single) {
      frame = Uint8Array.from(this.fragments[0]);
      this.fragments = [null, null, null, null];
      const declared = frame[0] || 0;
      if (declared && frame.length < declared) return;
      if (declared) frame = frame.slice(0, declared);
    } else {
      const packetSize = this.fragments[0][0];
      if (!packetSize || packetSize > 64) {
        this.fragments = [null, null, null, null];
        return;
      }
      const needed = Math.ceil(packetSize / 16);
      for (let i = 0; i < needed; i += 1) {
        if (!this.fragments[i]) return;
      }
      const combined = [];
      for (let i = 0; i < needed; i += 1) combined.push(...this.fragments[i]);
      frame = Uint8Array.from(combined.slice(0, packetSize));
      this.fragments = [null, null, null, null];
    }
    if (xorCrc(frame) !== 0) {
      this.log(`CRC error: ${bytesToHex(frame)}`);
      return;
    }
    if (frame.length < 8) return;
    const type = bytesToHex(frame.slice(1, 3));
    const addr = bytesToHex(frame.slice(3, 5));
    const dataLen = frame[5];
    let payload;
    if (type === "8100") payload = frame.slice(6, 6 + dataLen);
    else payload = frame.slice(6, 7);
    if (this.pending && (type === this.pending.expect || type === "8f00")) {
      this.pending.resolve({ type, addr, payload });
      this.pending = null;
    }
  }

  async command(body, expectType) {
    const cmd = xorCrc(body) === 0 && body.length >= 8 ? body : withXor(body.slice(0, -1));
    const expect = expectType || `${(cmd[1] | 0x80).toString(16).padStart(2, "0")}${cmd[2].toString(16).padStart(2, "0")}`;
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const reply = this.waitReply(expect, 5000);
      const width = this.single ? Math.max(16, cmd.length) : 16;
      for (let i = 0, ch = 0; i < cmd.length; i += width, ch += 1) {
        const slice = cmd.slice(i, i + width);
        await writeChar(this.txChars[ch], slice, !this.single);
      }
      try {
        const got = await reply.promise;
        if (got.type === "8f00" && expect !== "8f00") {
          throw new Error(`Device error frame 0x8f00 code 0x${got.payload[0].toString(16)}`);
        }
        return got;
      } catch (err) {
        this.log(`TX retry ${attempt + 1}/4: ${err.message}`);
        await delay(250);
      }
    }
    throw new Error("No memory-protocol reply");
  }

  waitReply(expect, timeoutMs) {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
      resolve = res;
      reject = rej;
    });
    const timer = setTimeout(() => {
      if (this.pending && this.pending.expect === expect) this.pending = null;
      reject(new Error("timeout"));
    }, timeoutMs);
    this.pending = {
      expect,
      resolve: (value) => {
        clearTimeout(timer);
        resolve(value);
      },
    };
    return { promise };
  }

  async readBlock(address, size) {
    const cmd = new Uint8Array(8);
    cmd[0] = 0x08;
    cmd[1] = 0x01;
    cmd[2] = 0x00;
    cmd[3] = (address >> 8) & 0xff;
    cmd[4] = address & 0xff;
    cmd[5] = size & 0xff;
    const reply = await this.command(withXor(cmd.slice(0, 7)), "8100");
    const gotAddr = parseInt(reply.addr, 16);
    if (gotAddr !== address) {
      throw new Error(`Address mismatch 0x${reply.addr} vs 0x${address.toString(16)}`);
    }
    return reply.payload;
  }

  async readRange(start, length) {
    const out = [];
    let addr = start;
    let left = length;
    while (left > 0) {
      const chunk = Math.min(left, this.profile.blockSize);
      const data = await this.readBlock(addr, chunk);
      out.push(...data);
      addr += chunk;
      left -= chunk;
    }
    return Uint8Array.from(out);
  }

  async writeBlock(address, data) {
    const prefix = new Uint8Array(6 + data.length + 1);
    prefix[0] = data.length + 8;
    prefix[1] = 0x01;
    prefix[2] = 0xc0;
    prefix[3] = (address >> 8) & 0xff;
    prefix[4] = address & 0xff;
    prefix[5] = data.length;
    prefix.set(data, 6);
    prefix[6 + data.length] = 0x00;
    const reply = await this.command(withXor(prefix), "81c0");
    const gotAddr = parseInt(reply.addr, 16);
    if (gotAddr !== address) {
      throw new Error(`Write address mismatch 0x${reply.addr}`);
    }
  }

  async closeMemory() {
    if (!this.memoryOpen) return;
    await this.command(hexToBytes("080f000000000007"), "8f00");
    this.memoryOpen = false;
  }

  async openMemory() {
    if (this.memoryOpen) return;
    const start = hexToBytes("0800000000100018");
    const reply = await this.command(start, "8000");
    if (reply.payload[0]) {
      throw new Error(`Device rejected memory session (0x${reply.payload[0].toString(16)})`);
    }
    this.memoryOpen = true;
  }

  decodeEepromTime(cached) {
    const layout = this.profile.timeLayout;
    const b = cached;
    try {
      let year;
      let month;
      let day;
      let hour;
      let minute;
      let second;
      if (layout === "modern_offset8") {
        [year, month, day, hour, minute, second] = [b[8], b[9], b[10], b[11], b[12], b[13]];
      } else if (layout === "classic_offset8") {
        [month, year, hour, day, second, minute] = [b[8], b[9], b[10], b[11], b[12], b[13]];
      } else if (layout === "linear_10") {
        [year, month, day, hour, minute, second] = [b[2], b[3], b[4], b[5], b[6], b[7]];
      } else {
        [month, year, hour, day, second, minute] = [b[2], b[3], b[4], b[5], b[6], b[7]];
      }
      return new Date(2000 + year, month - 1, day, hour, minute, Math.min(second, 59));
    } catch {
      return null;
    }
  }

  encodeEepromTime(cached, now) {
    const y = now.getFullYear() - 2000;
    const layout = this.profile.timeLayout;
    if (layout === "modern_offset8") {
      const result = [...cached.slice(0, 8), y, now.getMonth() + 1, now.getDate(), now.getHours(), now.getMinutes(), now.getSeconds()];
      result.push(result.reduce((a, b) => a + b, 0) & 0xff);
      result.push(0x00);
      return Uint8Array.from(result);
    }
    if (layout === "classic_offset8") {
      const result = [...cached.slice(0, 8), now.getMonth() + 1, y, now.getHours(), now.getDate(), now.getSeconds(), now.getMinutes()];
      result.push(result.reduce((a, b) => a + b, 0) & 0xff);
      result.push(0x00);
      return Uint8Array.from(result);
    }
    if (layout === "linear_10") {
      const result = [...cached.slice(0, 2), y, now.getMonth() + 1, now.getDate(), now.getHours(), now.getMinutes(), now.getSeconds(), 0x00];
      result.push(result.reduce((a, b) => a + b, 0) & 0xff);
      return Uint8Array.from(result);
    }
    const result = [
      ...cached.slice(0, 2),
      now.getMonth() + 1,
      y,
      now.getHours(),
      now.getDate(),
      now.getSeconds(),
      now.getMinutes(),
      0x00,
    ];
    result.push(result.reduce((a, b) => a + b, 0) & 0xff);
    return Uint8Array.from(result);
  }

  async syncEepromTime() {
    const p = this.profile;
    if (p.settingsRead == null || p.settingsWrite == null || !p.timeSync) {
      return false;
    }
    const [sectionStart, sectionEnd] = p.timeSync;
    const size = sectionEnd - sectionStart;
    const cached = await this.readRange(p.settingsRead + sectionStart, size);
    const deviceDt = this.decodeEepromTime(cached);
    const now = new Date();
    if (deviceDt && !Number.isNaN(deviceDt.getTime())) {
      const diff = Math.abs(now.getTime() - deviceDt.getTime()) / 1000;
      this.log(`Cuff clock ${deviceDt.toLocaleString()} (delta ${Math.round(diff)}s)`);
      if (diff <= 60) {
        this.log("Clock already within 60s; skipping EEPROM write");
        return true;
      }
    } else {
      this.log("Cuff clock unreadable; writing computer time");
    }
    const payload = this.encodeEepromTime(cached, now);
    await this.writeBlock(p.settingsWrite + sectionStart, payload);
    await delay(1000);
    this.log(`Wrote cuff clock ${now.toLocaleString()}`);
    return true;
  }

  async syncCtsTime() {
    try {
      const svc = await this.server.getPrimaryService(SVC_CTS);
      const cts = await svc.getCharacteristic(CHAR_CTS);
      const now = new Date();
      const payload = new Uint8Array(10);
      payload[0] = now.getFullYear() & 0xff;
      payload[1] = (now.getFullYear() >> 8) & 0xff;
      payload[2] = now.getMonth() + 1;
      payload[3] = now.getDate();
      payload[4] = now.getHours();
      payload[5] = now.getMinutes();
      payload[6] = now.getSeconds();
      payload[7] = now.getDay() === 0 ? 7 : now.getDay();
      await cts.writeValueWithResponse(payload);
      this.log("Wrote Current Time Service");
      try {
        const lti = await svc.getCharacteristic(CHAR_LTI);
        const offsetMins = -now.getTimezoneOffset();
        const tz15 = Math.trunc(offsetMins / 15) & 0xff;
        await lti.writeValueWithResponse(Uint8Array.from([tz15, 0x00]));
      } catch {
        /* optional */
      }
      return true;
    } catch (err) {
      this.log(`CTS not available (${err.message})`);
      return false;
    }
  }

  async syncTime() {
    let eeprom = false;
    if (this.profile.timeSync) {
      await this.openMemory();
      eeprom = await this.syncEepromTime();
    }
    try {
      await this.closeMemory();
    } catch (err) {
      this.log(`Memory close before CTS: ${err.message}`);
    }
    const cts = await this.syncCtsTime();
    try {
      await this.openMemory();
    } catch (err) {
      this.log(`Could not reopen memory session: ${err.message}`);
    }
    if (!eeprom && !cts) {
      throw new Error("Neither EEPROM nor CTS time sync succeeded");
    }
    return { eeprom, cts };
  }

  async pullReadings() {
    const startedAt = performance.now();
    try {
      return await this.readAllUsers();
    } finally {
      this.lastPollSeconds = (performance.now() - startedAt) / 1000;
    }
  }

  async readAllUsers() {
    const parse = this.profile.parser === "vital14bit" ? parseVital14Bit : parseVital14;
    const readings = [];
    for (let user = 0; user < this.profile.userStart.length; user += 1) {
      const base = this.profile.userStart[user];
      const count = this.profile.recordCount[user];
      const size = this.profile.recordSize;
      this.log(`Reading user ${user + 1}: 0x${base.toString(16)} × ${count}`);
      const raw = await this.readRange(base, count * size);
      for (let slot = 0; slot < count; slot += 1) {
        const rec = raw.slice(slot * size, slot * size + size);
        if ([...rec].every((b) => b === 0xff)) continue;
        try {
          const parsed = parse(rec);
          if (!plausible(parsed)) continue;
          readings.push({ user: user + 1, slot, ...parsed });
        } catch {
          /* empty or unparsable */
        }
      }
    }
    readings.sort((a, b) => {
      const ta = a.datetime ? a.datetime.getTime() : 0;
      const tb = b.datetime ? b.datetime.getTime() : 0;
      return tb - ta;
    });
    return readings;
  }
}

function waitFor(pred, timeoutMs) {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  const timer = setTimeout(() => reject(new Error("notify timeout")), timeoutMs);
  const listener = (event) => {
    const data = new Uint8Array(event.target.value.buffer);
    if (pred(data)) {
      clearTimeout(timer);
      resolve(data);
    }
  };
  return { promise, listener };
}

async function writeChar(char, data, withResponse) {
  const copy = Uint8Array.from(data);
  if (withResponse) {
    await char.writeValueWithResponse(copy);
    return;
  }
  try {
    await char.writeValueWithoutResponse(copy);
  } catch {
    await char.writeValueWithResponse(copy);
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
