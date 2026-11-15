# Сайт BREAKPOINT

`landing/` содержит страницу игры и экран запуска. `game-build/` содержит свежий экспорт Godot для браузера. Сборка сайта кладёт в `dist/` только эти файлы, изображения и публичную конфигурацию. Архивы Windows и macOS скачиваются напрямую из Blob или с другого хранилища по HTTPS.

## Vercel

1. Подключите репозиторий. **Root Directory** — `web`, Framework Preset — **Other**, команда сборки — `npm run build`, выходная папка — `dist`.
2. Укажите `BREAKPOINT_WINDOWS_URL` и `BREAKPOINT_MACOS_URL` для опубликованных архивов. macOS-архив выкладывается после подписи Developer ID и нотариального заверения Apple.
3. Для браузерных пряток запустите `online-relay` на VPS по [инструкции](../online-relay/README.md) и задайте `BREAKPOINT_RELAY_URL=wss://ваш-домен/rooms`. Vercel размещает сайт и WebAssembly. Постоянное WebSocket-соединение обслуживает ретранслятор.
4. Опубликуйте новую сборку после изменения переменных. Откройте `/play/`, создайте комнату и проверьте матч в двух браузерах из разных сетей. Коды браузерных комнат действуют на компактной «Арене». Для матча между Windows и macOS участникам нужна настольная версия.

## Локальная проверка

Запустите `npm ci` и `npm start` в `../online-relay`. В папке `web` запустите `npm run dev` с переменными `BREAKPOINT_LOCAL=1` и `BREAKPOINT_RELAY_URL=ws://127.0.0.1:8787/rooms`. Откройте `http://127.0.0.1:8080/play/`.

## Экспорт новой игры для сайта

Используйте Godot 4.7.2, шаблон Web с именем `web_dlink_nothreads_release.zip`, Emscripten 4.0.11 и свежий `voxcore.wasm`. Запустите `build_web.ps1` из корня, передав `-Godot`, `-Template`, `-Wasm` и путь пустой папки `-Stage`. Windows-редактор дополнительно использует `game/bin/voxcore.dll` для импорта. Экспорт обновит `web/game-build/`. `npm run build` повторно соберёт сайт с новыми файлами.
