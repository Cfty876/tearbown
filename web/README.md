# Сайт BREAKPOINT

`landing/` содержит страницу игры и экран запуска. `game-build/` содержит свежий экспорт Godot для браузера. Сборка сайта кладёт в `dist/` только эти файлы, изображения и публичную конфигурацию. Архивы Windows и macOS скачиваются напрямую из Blob или с другого хранилища по HTTPS.

## Vercel

1. Подключите репозиторий. **Root Directory** — `web`, Framework Preset — **Other**, команда сборки — `npm run build`, выходная папка — `dist`.
2. Опубликуйте ZIP для Windows и macOS на GitHub Releases. Сайт и настольные клиенты получают ссылки и контрольные суммы из `desktop-release.json`. Без этого файла сайт может использовать `BREAKPOINT_WINDOWS_URL` и `BREAKPOINT_MACOS_URL`.
3. Подключите Redis через Vercel Marketplace и включите Fluid Compute. Функция `/api/rooms` читает закрытую строку подключения из `BREAKPOINT_REDIS_URL`, `REDIS_URL` или `KV_URL`. Для Франкфурта используйте регион Redis `fra1`. HTTP-запрос `GET /api/rooms` проверяет доступ к Redis.
4. Задайте `BREAKPOINT_RELAY_URL=wss://ваш-домен/api/rooms` и повторите сборку. Для настольных клиентов укажите тот же адрес в форме комнаты или в `online.cfg`. Используйте новые сборки с переподключением. На «Арене» игроки в браузере, Windows и macOS версии 1.1.3 могут войти в одну комнату по общему коду. Остальные карты доступны в настольном приложении.
5. Проверьте вход и матч из двух разных сетей, а также продолжение раунда после смены соединения. Vercel ограничивает длительность WebSocket. Клиент восстанавливает комнату по служебному ключу, а Redis возвращает пропущенные надёжные события. Позиции передаются заново в следующем кадре.

## Выпуск обновления

1. Увеличьте `application/config/version` в `game/project.godot` и версии macOS в `game/export_presets.cfg`. Соберите настольные архивы.
2. Создайте GitHub-релиз с тегом вида `breakpoint-v1.1.0` и файлами `BREAKPOINT-Windows-x64.zip` и `BREAKPOINT-macOS.zip`.
3. Из корня проекта выполните `python tools/make_release_manifest.py 1.1.0 --windows <windows.zip> --macos <macos.zip> --output web/desktop-release.json`. Флаг `--macos-notarized` используйте после успешной проверки нотариального заверения Apple.
4. Опубликуйте GitHub-релиз и разверните сайт с новым манифестом. Игра проверяет версию при открытии главного меню, сверяет размер и SHA-256 загруженного ZIP и открывает его для установки. Клиент с версией до 1.1.0 нужно один раз обновить через сайт.

## Локальная проверка

С работающим Redis запустите из `web` сервер командой `npm run rooms:local` и переменной `BREAKPOINT_REDIS_URL=redis://127.0.0.1:6379`. Для сайта используйте `npm run dev` с `BREAKPOINT_LOCAL=1` и `BREAKPOINT_RELAY_URL=ws://127.0.0.1:8787/api/rooms`. Откройте `http://127.0.0.1:8080/play/`. Для теста двух экземпляров задействуйте `npm test` с `BREAKPOINT_TEST_REDIS_URL`.

## Экспорт новой игры для сайта

Используйте Godot 4.7.2, шаблон Web с именем `web_dlink_nothreads_release.zip`, Emscripten 4.0.11 и свежий `voxcore.wasm`. Запустите `build_web.ps1` из корня, передав `-Godot`, `-Template`, `-Wasm` и путь пустой папки `-Stage`. Windows-редактор дополнительно использует `game/bin/voxcore.dll` для импорта. Экспорт обновит `web/game-build/`. `npm run build` повторно соберёт сайт с новыми файлами.
