import telebot
import requests
from io import BytesIO
import time
import random
import json

TOKEN = '8479387303:AAFs2042KePw6Zw_Mvzsko5jMDQ9f3TiL_k'
bot = telebot.TeleBot(TOKEN)

MODELS_CACHE = {}
CACHE_TTL = 3600  # 1 час

def get_available_models():
    """Запрашивает актуальный список моделей из API"""
    current_time = time.time()
    if MODELS_CACHE and (current_time - MODELS_CACHE.get('updated', 0)) < CACHE_TTL:
        return MODELS_CACHE['list']
    
    try:
        resp = requests.get("https://image.pollinations.ai/models", timeout=10)
        resp.raise_for_status()
        models = json.loads(resp.text)  # JSON-массив строк
        models = [m.lower().strip() for m in models if m and len(m) < 50]  # Очистка
        models = sorted(list(set(models)))  # Уникальные
        
        # Fallback, если пусто
        if not models:
            models = ['flux', 'turbo', 'flux-realism', 'flux-anime', 'kontext', 'nanobanana', 'seedream', 'boltning']
        
        MODELS_CACHE['list'] = models
        MODELS_CACHE['updated'] = current_time
        print(f"Загружено моделей: {len(models)} — {models}")
        return models
    except Exception as e:
        print(f"Ошибка получения моделей: {e}")
        return ['flux', 'turbo', 'kontext', 'boltning']  # Минимальный fallback

@bot.message_handler(commands=['start'])
def start_message(message):
    markup = telebot.types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn = telebot.types.KeyboardButton("🔄 Обновить модели")
    markup.add(btn)
    bot.reply_to(message, 
                 "Привет! Отправь промпт — сгенерирую уникальные картинки на **всех актуальных моделях** из API.\n"
                 "Кнопка обновит список. Подожди: API даёт 8–12 моделей, каждая с рандомным seed для разнообразия.",
                 reply_markup=markup)

@bot.message_handler(func=lambda m: m.text == "🔄 Обновить модели")
def refresh_models(message):
    bot.reply_to(message, "Обновляю список из API...")
    models = get_available_models()
    short_list = ', '.join(models[:10]) + ('...' if len(models)>10 else '')
    bot.reply_to(message, f"Актуально {len(models)} моделей: {short_list}\n(flux, turbo, kontext, gptimage и др.)")

@bot.message_handler(func=lambda message: True)
def generate_images(message):
    prompt = message.text.strip()
    if not prompt or prompt == "🔄 Обновить модели":
        return
    
    bot.reply_to(message, f"Генерирую для: _{prompt}_\n\nЗагружаю модели из API...")
    
    models = get_available_models()
    bot.reply_to(message, f"Найдено {len(models)} моделей. Старт генерации (каждая с уникальным seed)...")
    
    sent = 0
    for model in models:
        try:
            encoded = requests.utils.quote(prompt)
            seed = random.randint(0, 9999)  # Рандом для уникальности
            url = f"https://image.pollinations.ai/prompt/{encoded}?model={model}&width=512&height=512&nologo=true&seed={seed}&enhance=true&private=true&safe=false"
            
            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            
            if 'error' in resp.text.lower() or len(resp.content) < 1000:  # Проверка на ошибку (маленький ответ)
                print(f"Модель {model} вернула ошибку, пропускаю")
                continue
            
            img = BytesIO(resp.content)
            img.name = f"{model}.jpg"
            caption = f"Модель: *{model}*\nПромпт: _{prompt}_\n(Seed: {seed})"
            bot.send_photo(message.chat.id, img, caption=caption, parse_mode='Markdown')
            sent += 1
            time.sleep(1.5)  # Пауза для стабильности
        except Exception as e:
            print(f"Ошибка модели {model}: {e}")
            continue
    
    bot.reply_to(message, f"Готово! Успешно: {sent}/{len(models)}. Если мало — обнови модели или проверь промпт (API иногда фильтрует). Ещё?")

if __name__ == '__main__':
    print("Бот запущен. Загружаю модели...")
    print("Доступно:", get_available_models())
    bot.polling(none_stop=True)
