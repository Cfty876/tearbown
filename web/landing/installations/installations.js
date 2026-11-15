const byId = id => document.getElementById(id);
let key = "";
let offset = 0;
let version = "";
const date = new Intl.DateTimeFormat("ru", { dateStyle: "medium", timeStyle: "short" });

function message(value) { byId("message").textContent = value; }

async function request(path, body) {
  const response = await fetch("/api/installations" + path, {
    method: body ? "POST" : "GET", cache: "no-store",
    headers: { Authorization: "Bearer " + key, ...(body && { "Content-Type": "application/json" }) },
    ...(body && { body: JSON.stringify(body) }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error);
  return data;
}

function selected() { return [...byId("rows").querySelectorAll("input:checked")].map(input => input.value); }
function selectionChanged() { byId("send").disabled = !version || selected().length === 0; }

async function refresh() {
  const data = await request("?offset=" + offset);
  byId("rows").replaceChildren();
  for (const entry of data.devices) {
    const row = byId("rows").insertRow();
    const check = document.createElement("input");
    check.type = "checkbox";
    check.value = entry.id;
    check.setAttribute("aria-label", "Выбрать установку " + entry.id.slice(0, 8));
    check.addEventListener("change", selectionChanged);
    row.insertCell().append(check);
    const status = entry.target && entry.version === entry.target ? "Установлено" : entry.target ? "Предложено " + entry.target : "—";
    for (const value of [entry.id.slice(0, 8), entry.platform, entry.version,
      date.format(entry.seen), status]) row.insertCell().textContent = value;
  }
  byId("all").checked = false;
  byId("back").disabled = offset === 0;
  byId("next").disabled = !data.more;
  byId("devices").hidden = false;
  selectionChanged();
  if (!data.devices.length) message("На этой странице пока нет установок.");
}

async function load() {
  try { message(""); await refresh(); }
  catch (error) { message(error.message); }
}

byId("login").addEventListener("submit", async event => {
  event.preventDefault();
  key = byId("access").value.trim();
  offset = 0;
  try {
    const manifest = await (await fetch("/desktop-release.json", { cache: "no-store" })).json();
    version = manifest.version;
    await refresh();
    byId("login").hidden = true;
    byId("access").value = "";
    message("Текущий выпуск — " + version);
  } catch (error) { key = ""; message(error.message); }
});
byId("refresh").onclick = load;
byId("back").onclick = () => { offset = Math.max(0, offset - 50); load(); };
byId("next").onclick = () => { offset += 50; load(); };
byId("all").onchange = event => {
  for (const input of byId("rows").querySelectorAll("input")) input.checked = event.target.checked;
  selectionChanged();
};
byId("send").onclick = async () => {
  byId("send").disabled = true;
  try {
    const result = await request("?admin=1", { ids: selected(), version });
    await refresh();
    message("Обновление предложено устройствам: " + result.sent);
  } catch (error) { message(error.message); }
  finally { selectionChanged(); }
};
