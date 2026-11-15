# Сайт BREAKPOINT

`landing/` содержит страницу игры и экран запуска. `game-build/` содержит свежий экспорт Godot для браузера. Сборка сайта кладёт в `dist/` только эти файлы, изображения и публичную конфигурацию. Архивы Windows и macOS скачиваются напрямую из Blob или с другого хранилища по HTTPS.

## Vercel

1. Подключите репозиторий. **Root Directory** — `web`, Framework Preset — **Other**, команда сборки — `npm run build`, выходная папка — `dist`.
2. Укажите `BREAKPOINT_WINDOWS_URL` и `BREAKPOINT_MACOS_URL` для опубликованных архивов. macOS-архив выкладывается после подписи Developer ID и нотариального заверения Apple.
3. Подключите Redis через Vercel Marketplace и включите Fluid Compute. Функция `/api/rooms` читает закрытую строку подключения из `BREAKPOINT_REDIS_URL`, `REDIS_URL` или `KV_URL`. Для Франкфурта используйте регион Redis `fra1`. HTTP-запрос `GET /api/rooms` проверяет доступ к Redis.
4. Задайте `BREAKPOINT_RELAY_URL=wss://ваш-домен/api/rooms` и повторите сборку. Для настольных клиентов укажите тот же адрес в форме комнаты или в `online.cfg`. Используйте новые сборки с переподключением. Коды браузерных комнат действуют на «Арене». Windows и macOS используют настольные комнаты.
5. Проверьте вход и матч из двух разных сетей, а также продолжение раунда после смены соединения. Vercel ограничивает длительность WebSocket. Клиент восстанавливает комнату по служебному ключу, а Redis возвращает пропущенные надёжные события. Позиции передаются заново в следующем кадре.

## Локальная проверка

С работающим Redis запустите из `web` сервер командой `npm run rooms:local` и переменной `BREAKPOINT_REDIS_URL=redis://127.0.0.1:6379`. Для сайта используйте `npm run dev` с `BREAKPOINT_LOCAL=1` и `BREAKPOINT_RELAY_URL=ws://127.0.0.1:8787/api/rooms`. Откройте `http://127.0.0.1:8080/play/`. Для теста двух экземпляров задействуйте `npm test` с `BREAKPOINT_TEST_REDIS_URL`.

## Экспорт новой игры для сайта

Используйте Godot 4.7.2, шаблон Web с именем `web_dlink_nothreads_release.zip`, Emscripten 4.0.11 и свежий `voxcore.wasm`. Запустите `build_web.ps1` из корня, передав `-Godot`, `-Template`, `-Wasm` и путь пустой папки `-Stage`. Windows-редактор дополнительно использует `game/bin/voxcore.dll` для импорта. Экспорт обновит `web/game-build/`. `npm run build` повторно соберёт сайт с новыми файлами.
