#!/bin/bash

# Install.sh — Полная автоустановка ImageGen бота (Pollinations API)
# Работает: Ubuntu/Debian/CentOS/macOS
# Автор: SCRIBE для Павла

set -e

REPO_URL="https://github.com/PavloMakaro/Imagegen.git"
BRANCH="main"
BOT_DIR="Imagegen"
VENV_DIR="$BOT_DIR/venv"
BOT_FILE="$BOT_DIR/bot.py"
REQUIREMENTS="$BOT_DIR/requirements.txt"

echo "🚀 Запуск установки ImageGen бота..."

# 1. Системные пакеты
echo "📦 Установка python3, git..."
if command -v apt-get >/dev/null; then
    sudo apt-get update -y && sudo apt-get install -y python3 python3-venv python3-pip git curl
elif command -v yum >/dev/null; then
    sudo yum update -y && sudo yum install -y python3 python3-venv git curl
elif command -v brew >/dev/null; then
    brew install python3 git
else
    echo "⚠️ Установите python3 и git вручную."
    exit 1
fi

# 2. Клонируем/обновляем репо
if [ -d "$BOT_DIR" ]; then
    echo "📥 Обновляю репо..."
    cd $BOT_DIR && git pull origin $BRANCH && cd ..
else
    echo "📥 Клонирую репо..."
    git clone --branch $BRANCH $REPO_URL $BOT_DIR
fi
cd $BOT_DIR

# 3. Виртуальное окружение
echo "🐍 Создаю venv..."
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

# 4. requirements.txt — фикс!
echo "📚 Установка зависимостей..."
cat > $REQUIREMENTS << EOF
pyTelegramBotAPI
requests
EOF
pip install --upgrade pip
pip install -r $REQUIREMENTS

# 5. bot.py — свежий код с /models и random seed
echo "🤖 Создаю/обновляю bot.py..."
cat > $BOT_FILE << 'EOF'
import telebot
import requests
from io import BytesIO
import time
import random
import json

TOKEN = '8479387303:AAFs2042KePw6Zw_Mvzsko5jMDQ9f3TiL_k'
bot = telebot.TeleBot(TOKEN)

MODELS_CACHE = {}
CACHE_TTL = 3600

def get_available_models():
    current_time = time.time()
    if MODELS_CACHE and (current_time - MODELS_CACHE.get('updated', 0)) < CACHE_TTL:
        return MODELS_CACHE['list']
    
    try:
        resp = requests.get("https://image.pollinations.ai/models", timeout=10)
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, list):
            models = [m.lower().strip() for m in data if isinstance(m, str) and m.strip()]
        else:
            models = []
        
        models = sorted(list(set(models)))
        
        if not models:
            models = ['flux', 'turbo', 'flux-anime', 'flux-dev', 'kontext', 'boltning', 'nanobanana', 'seedream']
        
        MODELS_CACHE['list'] = models
        MODELS_CACHE['updated'] = current_time
        print(f"Модели ({len(models)}): {models}")
        return models
    except Exception as e:
        print(f"Ошибка моделей: {e}")
        return ['flux', 'turbo', 'kontext', 'boltning']

@bot.message_handler(commands=['start'])
def start_message(message):
    markup = telebot.types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn = telebot.types.KeyboardButton("Обновить модели")
    markup.add(btn)
    bot.reply_to(message, 
                 "Привет! Промпт — и генерирую **уникальные** картинки на **всех моделях** из API (10–15+).\n"
                 "Кнопка — обновить список.", reply_markup=markup)

@bot.message_handler(func=lambda m: m.text == "Обновить модели")
def refresh_models(message):
    bot.reply_to(message, "Загружаю модели из API...")
    models = get_available_models()
    short = ', '.join(models[:12]) + ('...' if len(models)>12 else '')
    bot.reply_to(message, f"{len(models)} моделей: {short}")

@bot.message_handler(func=lambda message: True)
def generate_images(message):
    prompt = message.text.strip()
    if not prompt or prompt == "Обновить модели":
        return
    
    bot.reply_to(message, f"Генерация: _{prompt}_\n\nМодели: загружаю...")
    models = get_available_models()
    bot.reply_to(message, f"{len(models)} моделей. Старт (уникальный seed на каждую)...")
    
    sent = 0
    for model in models:
        try:
            encoded = requests.utils.quote(prompt)
            seed = random.randint(1, 999999)
            url = f"https://image.pollinations.ai/prompt/{encoded}?model={model}&width=512&height=512&nologo=true&seed={seed}&enhance=true&private=true&safe=false"
            
            resp = requests.get(url, timeout=30)
            if resp.status_code != 200 or len(resp.content) < 5000:
                print(f"{model}: ошибка {resp.status_code}")
                continue
            
            img = BytesIO(resp.content)
            img.name = f"{model}.jpg"
            caption = f"*{model}*\n_{prompt}_\nSeed: {seed}"
            bot.send_photo(message.chat.id, img, caption=caption, parse_mode='Markdown')
            sent += 1
            time.sleep(1.5)
        except Exception as e:
            print(f"{model}: {e}")
            continue
    
    bot.reply_to(message, f"Готово: {sent}/{len(models)}. Ещё промпт?")

if __name__ == '__main__':
    print("Бот запущен...")
    get_available_models()
    bot.polling(none_stop=True)
EOF

# 6. systemd-сервис
echo "🛠 Настраиваю автозапуск..."
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

# 7. Финал
echo "✅ Установка завершена!"
echo ""
echo "Запуск: sudo systemctl start imagegen-bot"
echo "Статус: sudo systemctl status imagegen-bot"
echo "Логи: journalctl -u imagegen-bot -f"
echo ""
echo "Однострочник для новых серверов:"
echo "wget -O Install.sh https://raw.githubusercontent.com/PavloMakaro/Imagegen/main/Install.sh && chmod +x Install.sh && ./Install.sh"

read -p "Запустить бота сейчас? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl start imagegen-bot
    echo "Бот запущен! Проверяй в Telegram."
fi
