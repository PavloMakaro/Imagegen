import telebot
import requests
from io import BytesIO
import re
import time

TOKEN = '8479387303:AAFs2042KePw6Zw_Mvzsko5jMDQ9f3TiL_k'
bot = telebot.TeleBot(TOKEN)

# Кэш моделей: {model_name: last_updated}
MODELS_CACHE = {}
CACHE_TTL = 3600  # 1 час

def get_available_models():
    """Извлекает все модели из API (парсит документацию или fallback)"""
    current_time = time.time()
    
    # Если кэш свежий — возвращаем
    if MODELS_CACHE and (current_time - MODELS_CACHE.get('updated', 0)) < CACHE_TTL:
        return MODELS_CACHE['list']
    
    try:
        # Пробуем получить с главной страницы (там есть JS с моделями)
        resp = requests.get("https://pollinations.ai/", timeout=10)
        resp.raise_for_status()
        
        # Ищем модели в JS или HTML (регулярка на model=...)
        models = set()
        patterns = [
            r'model["\']?:\s*["\']([^"\']+)["\']',
            r'data-model=["\']([^"\']+)["\']',
            r'/p/[^?]+\?model=([^&"\']+)'
        ]
        for pattern in patterns:
            found = re.findall(pattern, resp.text, re.I)
            models.update(found)
        
        # Fallback: известные модели
        fallback = ['flux', 'turbo', 'kontext', 'boltning', 'flux-dev', 'flux-schnell']
        models = models or fallback
        
        models = [m.lower() for m in models if m and len(m) < 30]
        models = sorted(list(set(models)))  # Уникальные, отсортированные
        
        # Кэшируем
        MODELS_CACHE['list'] = models
        MODELS_CACHE['updated'] = current_time
        return models
        
    except Exception as e:
        print(f"Ошибка парсинга моделей: {e}")
        return ['flux', 'turbo', 'kontext', 'boltning']  # Надёжный fallback

@bot.message_handler(commands=['start'])
def start_message(message):
    markup = telebot.types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn = telebot.types.KeyboardButton("🔄 Обновить модели")
    markup.add(btn)
    bot.reply_to(message, 
                 "Привет! Отправь промпт — сгенерирую картинки на **всех моделях**.\n"
                 "Или нажми кнопку ниже, чтобы обновить список моделей.",
                 reply_markup=markup)

@bot.message_handler(func=lambda m: m.text == "🔄 Обновить модели")
def refresh_models(message):
    bot.reply_to(message, "Обновляю список моделей...")
    models = get_available_models()
    bot.reply_to(message, f"Найдено {len(models)} моделей: {', '.join(models[:10])}{'...' if len(models)>10 else ''}")

@bot.message_handler(func=lambda message: True)
def generate_images(message):
    prompt = message.text.strip()
    if not prompt or prompt == "🔄 Обновить модели":
        return
    
    bot.reply_to(message, f"Генерирую для:\n_{prompt}_\n\nМоделей: подожди, определяю...")
    
    models = get_available_models()
    bot.reply_to(message, f"Найдено {len(models)} моделей. Генерация началась...")
    
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
            
            time.sleep(1)  # Чтобы не спамить и не словить бан
        except Exception as e:
            print(f"Ошибка {model}: {e}")
            continue
    
    summary = f"Готово! Отправлено: {sent}/{len(models)}"
    bot.reply_to(message, summary)

if __name__ == '__main__':
    print("Бот запущен. Извлекаю модели...")
    print("Доступно:", get_available_models())
    bot.polling(none_stop=True)
