const release = globalThis.BreakpointConfig ?? {};
for (const platform of ["windows", "macos"]) {
  if (!release[platform]) continue;
  const link = document.getElementById(platform + "-download");
  link.href = release[platform];
  link.hidden = false;
  document.getElementById(platform + "-status").hidden = true;
}
document.getElementById("online-status").textContent = release.relay
  ? "Для пряток открой игру, создай комнату и отправь её код другу."
  : "Сервер онлайн-комнат пока не подключён. Браузерная песочница доступна.";
