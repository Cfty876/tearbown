const release = globalThis.BreakpointConfig ?? {};
for (const platform of ["windows", "macos"]) {
  if (!release[platform]) continue;
  const link = document.getElementById(platform + "-download");
  link.href = release[platform];
  link.hidden = false;
  const status = document.getElementById(platform + "-status");
  if (release.version) {
    const isMacTrial = platform === "macos" && !release.macosNotarized;
    status.textContent = "Версия " + release.version + (isMacTrial ? " · тестовый выпуск" : "");
  } else {
    status.hidden = true;
  }
}
const patches = Object.entries(release.windowsPatches ?? {});
if (patches.length) {
  const list = document.getElementById("windows-patch-list");
  for (const [base, patch] of patches) {
    const row = document.createElement("li");
    const link = document.createElement("a");
    const size = (patch.size / 1048576).toLocaleString("ru-RU", { maximumFractionDigits: 1 });
    link.href = patch.url;
    link.textContent = `Патч с ${base} до ${release.version} · ${size} МБ`;
    row.append(link);
    list.append(row);
  }
  document.getElementById("windows-patches").hidden = false;
}
document.getElementById("macos-test").hidden = Boolean(release.macosNotarized);
document.getElementById("online-status").textContent = release.relay
  ? "Для пряток открой игру, создай комнату и отправь её код другу."
  : "Сервер онлайн-комнат пока не подключён. Браузерная песочница доступна.";
