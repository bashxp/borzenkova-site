#!/bin/sh
# Проверка собранного сайта перед публикацией. Запускается после `vite build`
# (локально — `npm run check`, в GitHub Actions — перед каждым деплоем).
# Любая ошибка здесь = сайт НЕ публикуется, на borzenkova.ru остаётся прошлая версия.
set -eu

MAX_FILE_KB=5120     # одна картинка — не больше 5 МБ
MAX_TOTAL_KB=51200   # весь сайт — не больше 50 МБ

fail=0
err() { echo "✗ $*" >&2; fail=1; }

[ -f dist/index.html ] || { echo "✗ нет dist/index.html — сборка не прошла" >&2; exit 1; }

# 1. Всё, на что ссылается index.html (скрипты, стили), лежит в сборке.
for ref in $(grep -o '\(src\|href\)="/assets/[^"]*"' dist/index.html | cut -d'"' -f2); do
  [ -f "dist$ref" ] || err "index.html ссылается на $ref, а файла нет"
done

# 2. Картинки из CSS (url(/assets/...)) существуют.
for ref in $(cat dist/assets/*.css 2>/dev/null | grep -o 'url(/assets/[^)]*)' | sed 's/^url(//; s/)$//' | sort -u); do
  [ -f "dist$ref" ] || err "стили ссылаются на $ref, а файла нет"
done

# 3. Картинки, подключённые в коде через asset('имя'), лежат в public/assets.
for name in $(grep -oh "asset('[^']*')" src/*.tsx | sed "s/^asset('//; s/')$//" | sort -u); do
  [ -f "public/assets/$name" ] || err "в коде asset('$name'), а файла public/assets/$name нет"
done

# 4. Размеры: тяжёлые файлы тормозят сайт на телефоне и забивают общий диск сервера.
for f in $(find dist -type f); do
  kb=$(( $(wc -c < "$f") / 1024 ))
  [ "$kb" -le "$MAX_FILE_KB" ] || err "$f весит ${kb} КБ — больше лимита ${MAX_FILE_KB} КБ, сожмите картинку"
done
total=$(du -sk dist | cut -f1)
[ "$total" -le "$MAX_TOTAL_KB" ] || err "сайт весит ${total} КБ — больше лимита ${MAX_TOTAL_KB} КБ"

# 5. Никаких симлинков: сервер их всё равно не отдаст, а в сборке им не место.
[ -z "$(find dist -type l)" ] || err "в dist/ есть символические ссылки: $(find dist -type l)"

if [ "$fail" -ne 0 ]; then
  echo "Проверка не пройдена — публикация остановлена." >&2
  exit 1
fi
echo "✓ сборка в порядке: $(find dist -type f | wc -l | tr -d ' ') файлов, ${total} КБ"
