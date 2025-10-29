#!/bin/bash

# install.sh — Автоустановка ImageGen бота из https://github.com/PavloMakaro/Imagegen
# Автор: SCRIBE (для Павла)

set -e  # Остановка при ошибке

REPO_URL="https://github.com/PavloMakaro/Imagegen.git"
BRANCH="main"
BOT_DIR="Imagegen"
VENV_DIR="$BOT_DIR/venv"
BOT_FILE="$BOT_DIR/bot.py"
REQUIREMENTS="$BOT_DIR/requirements.txt"

echo "🚀 Запуск установки ImageGen бота..."

# 1. Обновляем систему и ставим зависимости
echo "📦 Устанавливаем системные пакеты..."
if command -v apt-get >/dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-venv python3-pip git curl
elif command -v yum >/dev/null; then
    sudo yum update -y
    sudo yum install -y python3 python3-venv git curl
elif command -v brew >/dev/null; then
    brew install python3 git
else
    echo "⚠️ Неизвестный пакетный менеджер. Убедитесь, что python3 и git установлены."
fi

# 2. Клонируем репозиторий
echo "📥 Клонируем репозиторий..."
if [ -d "$BOT_DIR" ]; then
    echo "Папка $BOT_DIR уже существует — обновляю..."
    cd $BOT_DIR
    git pull origin $BRANCH
    cd ..
else
    git clone --branch $BRANCH $REPO_URL $BOT_DIR
fi

cd $BOT_DIR

# 3. Создаём виртуальное окружение
echo "🐍 Создаём виртуальное окружение..."
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

# 4. Устанавливаем Python-зависимости
echo "📚 Устанавливаем зависимости..."
if [ -f "$REQUIREMENTS" ]; then
    pip install --upgrade pip
    pip install -r $REQUIREMENTS
else
    echo "requirements.txt не найден — ставлю базовые..."
    pip install pyTelegramBotAPI requests
    echo "pyTelegramBotAPI\nrequests" > $REQUIREMENTS
fi

# 5. Проверяем, есть ли bot.py
if [ ! -f "$BOT_FILE" ]; then
    echo "⚠️ bot.py не найден! Создаю из последнего кода..."
    cat > $BOT_FILE << 'EOF'
import telebot
import requests
from io import BytesIO
import re
import time

TOKEN = '8479387303:AAFs2042KePw6Zw_Mvzsko5jMDQ9f3TiL_k'
bot = telebot.TeleBot(TOKEN)

MODELS_CACHE = {}
CACHE_TTL = 3600

def get_available_models():
    current_time = time.time()
    if MODELS_CACHE and (current_time - MODELS_CACHE.get('updated', 0)) < CACHE_TTL:
        return MODELS_CACHE['list']
    
    try:
        resp = requests.get("https://pollinations.ai/", timeout=10)
        resp.raise_for_status()
        models = set()
        patterns = [
            r'model["\']?:\s*["\']([^"\']+)["\']',
            r'data-model=["\']([^"\']+)["\']',
            r'/p/[^?]+\?model=([^&"\']+)'
        ]
        for pattern in patterns:
            found = re.findall(pattern, resp.text, re.I)
            models.update(found)
        
        fallback = ['flux', 'turbo', 'kontext', 'boltning', 'flux-dev', 'flux-schnell']
        models = models or fallback
        models = [m.lower() for m in models if m and len(m) < 30]
        models = sorted(list(set(models)))
        
        MODELS_CACHE['list'] = models
        MODELS_CACHE['updated'] = current_time
        return models
    except:
        return ['flux', 'turbo', 'kontext', 'boltning']

@bot.message_handler(commands=['start'])
def start_message(message):
    markup = telebot.types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn = telebot.types.KeyboardButton("🔄 Обновить модели")
    markup.add(btn)
    bot.reply_to(message, 
                 "Привет! Отправь промпт — сгенерирую на всех моделях.\n"
                 "Кнопка ниже — обновить модели.", reply_markup=markup)

@bot.message_handler(func=lambda m: m.text == "🔄 Обновить модели")
def refresh_models(message):
    bot.reply_to(message, "Обновляю...")
    models = get_available_models()
    bot.reply_to(message, f"Найдено {len(models)}: {', '.join(models[:10])}{'...' if len(models)>10 else ''}")

@bot.message_handler(func=lambda message: True)
def generate_images(message):
    prompt = message.text.strip()
    if not prompt or prompt == "🔄 Обновить модели":
        return
    
    bot.reply_to(message, f"Генерирую:\n_{prompt}_\n\nОпределяю модели...")
    models = get_available_models()
    bot.reply_to(message, f"Найдено {len(models)}. Старт...")
    
    sent = 0
    for i, model in enumerate(models):
        try:
            encoded = requests.utils.quote(prompt)
            url = f"https://pollinations.ai/p/{encoded}?model={model}&width=512&height=512&nologo=true&seed=-1&safe=true"
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            img = BytesIO(resp.content)
            img.name = f"{model}.jpg"
            caption = f"Модель: *{model}*\nПромпт: _{prompt}_"
            bot.send_photo(message.chat.id, img, caption=caption, parse_mode='Markdown')
            sent += 1
            time.sleep(1)
        except Exception as e:
            print(f"Ошибка {model}: {e}")
            continue
    
    bot.reply_to(message, f"Готово! Отправлено: {sent}/{len(models)}")

if __name__ == '__main__':
    print("Бот запущен...")
    bot.polling(none_stop=True)
EOF
    echo "bot.py создан."
fi

# 6. Создаём systemd-сервис (опционально)
echo "🛠 Создаём автозапуск (systemd)..."
sudo tee /etc/systemd/system/imagegen-bot.service > /dev/null << EOF
[Unit]
Description=ImageGen Pollinations Bot
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/$VENV_DIR/bin/python $(pwd)/$BOT_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable imagegen-bot.service

# 7. Запуск
echo "🎯 Установка завершена!"
echo ""
echo "Запустить вручную: cd $BOT_DIR && source venv/bin/activate && python bot.py"
echo "Или автозапуск: sudo systemctl start imagegen-bot"
echo "Проверить статус: sudo systemctl status imagegen-bot"
echo ""
echo "Репозиторий: $REPO_URL"
echo "Бот готов к работе, Павел! 🚀"

# Опционально: запуск сейчас
read -p "Запустить бота сейчас? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl start imagegen-bot
    echo "Бот запущен как сервис."
fi
