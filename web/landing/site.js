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
document.getElementById("macos-test").hidden = Boolean(release.macosNotarized);
document.getElementById("online-status").textContent = release.relay
  ? "Для пряток открой игру, создай комнату и отправь её код другу."
  : "Сервер онлайн-комнат пока не подключён. Браузерная песочница доступна.";
