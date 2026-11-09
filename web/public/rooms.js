(() => {
  const el = (id) => document.getElementById(id);
  const dialog = el("rooms");
  const codeInput = el("room-code");
  let callback;
  let session;
  let fragments = new Map();
  let serial = 0;

  function emit(kind, payload) {
    callback?.(kind, typeof payload === "string" ? payload : JSON.stringify(payload));
  }
  function status(text) { el("room-status").textContent = text; }
  function resetForm() {
    el("room-actions").hidden = false;
    el("room-invite").hidden = true;
  }
  function close(notify = false, reason = "") {
    const old = session;
    session = undefined;
    if (!old) return;
    old.abort.abort();
    clearTimeout(old.disconnected);
    old.peer?.close();
    fragments = new Map();
    if (notify && old.opened) emit("closed", reason);
  }
  function fail(current, error) {
    if (session !== current) return;
    const message = error.message || "Не удалось подключиться";
    if (current.opened) close(true, message);
    else {
      close();
      resetForm();
      status(message);
    }
  }
  async function request(current, action, extra = {}) {
    const response = await fetch("/api/room", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, code: current.code, token: current.token, ...extra }),
      signal: current.abort.signal,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error ?? "Сервис комнат недоступен");
    return data;
  }
  function signal(current, kind, value) {
    current.outgoing = current.outgoing.then(() => request(current, "signal", { signal: { kind, value } }));
    current.outgoing.catch((error) => fail(current, error));
    return current.outgoing;
  }
  function receive(data) {
    if (typeof data !== "string" || data.length > 65000) return;
    if (!data.startsWith("!")) {
      emit("packet", data);
      return;
    }
    let part;
    try { part = JSON.parse(data.slice(1)); } catch { return; }
    if (!Array.isArray(part) || part.length !== 4) return;
    const [id, index, count, text] = part;
    if (!Number.isInteger(index) || !Number.isInteger(count) || count < 2 || count > 100
        || index < 0 || index >= count || typeof text !== "string") return;
    if (index === 0) {
      if (fragments.size >= 8) return;
      fragments.set(id, []);
    }
    const batch = fragments.get(id);
    if (!batch || batch.length !== index) return;
    batch.push(text);
    if (batch.length === count) {
      fragments.delete(id);
      emit("packet", batch.join(""));
    }
  }
  function bindChannel(current, channel) {
    if (channel.label === "events") current.events = channel;
    else if (channel.label === "pose") current.pose = channel;
    else { channel.close(); return; }
    channel.onmessage = (event) => { if (session === current) receive(event.data); };
    channel.onopen = () => {
      if (session !== current || current.opened) return;
      if (current.events?.readyState !== "open" || current.pose?.readyState !== "open") return;
      current.opened = true;
      dialog.close();
      el("canvas").focus();
      emit("open", { host: current.host, code: current.code });
    };
    channel.onclose = () => fail(current, new Error("Друг отключился от комнаты"));
  }
  async function negotiate(current) {
    const peer = new RTCPeerConnection({ iceServers: current.iceServers });
    current.peer = peer;
    peer.onicecandidate = ({ candidate }) => {
      if (candidate && session === current && !current.opened) signal(current, "ice", candidate.toJSON());
    };
    peer.ondatachannel = ({ channel }) => bindChannel(current, channel);
    peer.onconnectionstatechange = () => {
      if (session !== current) return;
      clearTimeout(current.disconnected);
      if (peer.connectionState === "failed") fail(current, new Error("Соединение не установлено. Для этой сети может понадобиться TURN."));
      if (peer.connectionState === "disconnected") {
        current.disconnected = setTimeout(() => fail(current, new Error("Соединение с другом потеряно")), 5000);
      }
    };
    if (current.host) {
      bindChannel(current, peer.createDataChannel("events"));
      bindChannel(current, peer.createDataChannel("pose", { ordered: false, maxRetransmits: 0 }));
      await peer.setLocalDescription(await peer.createOffer());
      await signal(current, "offer", peer.localDescription.toJSON());
    }
    let cursor = 0;
    const waitingIce = [];
    const deadline = Date.now() + 9 * 60 * 1000;
    while (session === current && !current.opened) {
      if (Date.now() > deadline) throw new Error("Время ожидания комнаты истекло");
      const result = await request(current, "poll", { cursor });
      cursor = result.cursor;
      for (const { kind, value } of result.messages) {
        if (kind === "ice") {
          if (peer.remoteDescription) await peer.addIceCandidate(value);
          else waitingIce.push(value);
          continue;
        }
        await peer.setRemoteDescription(value);
        for (const candidate of waitingIce.splice(0)) await peer.addIceCandidate(candidate);
        if (kind === "offer") {
          await peer.setLocalDescription(await peer.createAnswer());
          await signal(current, "answer", peer.localDescription.toJSON());
        }
      }
      if (!current.opened) await new Promise((resolve) => setTimeout(resolve, 430));
    }
  }
  async function start(action) {
    close();
    const current = {
      code: codeInput.value.trim().toUpperCase(), abort: new AbortController(), outgoing: Promise.resolve(),
    };
    session = current;
    el("room-actions").hidden = true;
    status("Подключаемся…");
    try {
      Object.assign(current, await request(current, action));
      if (session !== current) return;
      if (current.host) {
        el("room-share").textContent = current.code;
        el("room-invite").hidden = false;
        status("Ждём второго игрока…");
      } else status("Соединяем устройства…");
      await negotiate(current);
    } catch (error) {
      fail(current, error);
    }
  }
  window.BreakpointRooms = {
    attach(listener) { callback = listener; },
    show() {
      if (dialog.open) return;
      resetForm();
      const invite = new URL(location.href).searchParams.get("room")?.toUpperCase();
      if (invite && /^[0-9A-F]{8}$/.test(invite)) codeInput.value = invite;
      status("");
      dialog.showModal();
    },
    send(text, reliable) {
      const channel = reliable ? session?.events : session?.pose;
      if (channel?.readyState !== "open" || (!reliable && channel.bufferedAmount > 24000)) return false;
      try {
        if (text.length <= 16000) channel.send(text);
        else {
          const count = Math.ceil(text.length / 16000);
          if (!reliable || count > 100) return false;
          const id = ++serial;
          for (let i = 0; i < count; i += 1) {
            channel.send("!" + JSON.stringify([id, i, count, text.slice(i * 16000, (i + 1) * 16000)]));
          }
        }
        return true;
      } catch { return false; }
    },
    close() { close(); },
  };
  el("create-room").addEventListener("click", () => start("create"));
  el("join-room").addEventListener("submit", (event) => { event.preventDefault(); start("join"); });
  el("close-room").addEventListener("click", () => { close(); dialog.close(); el("canvas").focus(); });
  dialog.addEventListener("cancel", () => close());
  el("copy-room").addEventListener("click", async () => {
    if (!session) return;
    const link = new URL(location.href);
    link.searchParams.set("room", session.code);
    try { await navigator.clipboard.writeText(link.href); status("Ссылка скопирована. Ждём друга…"); }
    catch { status("Отправь другу код " + session.code); }
  });
})();
