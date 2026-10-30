#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Скрываем навбар, если страница загружена в iframe (через JS)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Добавляем скрипт, который скрывает навбар, если страница в iframe
# Вставляем перед закрывающим тегом </body>
script = '''
<script>
  // Если страница загружена в iframe, скрываем навбар
  if (window.self !== window.top) {
    const nav = document.querySelector('nav.navbar');
    if (nav) nav.style.display = 'none';
    // Убираем отступы у main, чтобы контент занял всё место
    const main = document.querySelector('main');
    if (main) {
      main.classList.remove('pb-5');
      main.classList.add('pt-3');
    }
  }
</script>
'''

if 'window.self !== window.top' not in content:
    content = content.replace('</body>', script + '\n</body>')
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Скрипт скрытия навбара в iframe добавлен.")
else:
    print("ℹ️ Скрипт уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Второй навбар должен исчезнуть."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: hide navbar inside iframe using JS"