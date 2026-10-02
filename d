import os
import random
import asyncio
import logging
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes
import yt_dlp

# ================== AYARLAR ==================
BOT_TOKEN = os.getenv("8954865649:AAHwOFt2pY15y-q97_2LXodD4pDlegb1kZ0")          # Railway'de environment variable olarak koyacağız
ADMIN_ID = 1517523422

# Her kategori için arama terimleri
SEARCH_QUERIES = {
    "tayt": [
        "tight leggings",
        "yoga pants",
        "leggings fuck",
        "spandex ass",
        "tight pants tease"
    ],
    "ic_camasir": [
        "lingerie",
        "underwear tease",
        "bikini fuck",
        "panties",
        "bra and panties"
    ],
    "milf": [
        "milf",
        "hot milf",
        "mature milf",
        "milf fuck",
        "sexy milf"
    ],
    "genc": [
        "18 year old",
        "barely 18",
        "young 18",
        "petite 18",
        "teen 18+"
    ]
}

# Kullanılacak kaynaklar
SOURCES = [
    "ytsearch5:{}",           # YouTube
    "redditsearch5:{}",       # Reddit
    "twittersearch5:{}"       # Twitter / X  (bazen twitter: da çalışır)
]

DOWNLOAD_DIR = Path("downloads")
DOWNLOAD_DIR.mkdir(exist_ok=True)
# ============================================

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_keyboard():
    keyboard = [
        [InlineKeyboardButton("🔥 Tayt & Türevleri", callback_data="cat_tayt")],
        [InlineKeyboardButton("👙 İç Çamaşırı & Mayo/Bikini", callback_data="cat_ic_camasir")],
        [InlineKeyboardButton("👩‍🦰 MILF", callback_data="cat_milf")],
        [InlineKeyboardButton("👧 18+ Genç", callback_data="cat_genc")],
    ]
    return InlineKeyboardMarkup(keyboard)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("Bu bot sadece sahibi tarafından kullanılabilir.")
        return
    await update.message.reply_text(
        "Kategori seç → YouTube / Reddit / Twitter’dan video bulup atacağım.",
        reply_markup=get_keyboard()
    )

def download_video(query: str) -> str | None:
    """Birden fazla kaynaktan dener, ilk başarılı olanı indirir"""
    random.shuffle(SOURCES)  # Her seferinde farklı sırayla dene

    ydl_opts = {
        "format": "best[height<=720][ext=mp4]/best[ext=mp4]/best",
        "outtmpl": str(DOWNLOAD_DIR / "%(id)s.%(ext)s"),
        "quiet": True,
        "no_warnings": True,
        "max_filesize": 45 * 1024 * 1024,  # 45 MB
        "socket_timeout": 25,
        "retries": 2,
    }

    for source_template in SOURCES:
        search_url = source_template.format(query)
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(search_url, download=False)
                
                entries = []
                if info and "entries" in info:
                    entries = [e for e in info["entries"] if e]
                elif info:
                    entries = [info]

                if not entries:
                    continue

                entry = random.choice(entries)
                ydl.download([entry.get("webpage_url") or entry.get("url")])

                # İndirilen dosyayı bul
                video_id = entry.get("id")
                if video_id:
                    for file in DOWNLOAD_DIR.glob(f"{video_id}.*"):
                        return str(file)
                
                # id yoksa son eklenen dosyayı al
                files = list(DOWNLOAD_DIR.glob("*"))
                if files:
                    return str(max(files, key=os.path.getctime))

        except Exception as e:
            logger.warning(f"{search_url} başarısız: {e}")
            continue

    return None

async def send_random_video(query_list: list, chat_id: int, context: ContextTypes.DEFAULT_TYPE, category: str):
    query = random.choice(query_list)
    
    status_msg = await context.bot.send_message(
        chat_id, 
        f"🔍 {category.upper()} aranıyor...\n(YouTube / Reddit / Twitter)\n10-50 saniye sürebilir"
    )

    loop = asyncio.get_event_loop()
    file_path = await loop.run_in_executor(None, download_video, query)

    if not file_path or not os.path.exists(file_path):
        await status_msg.edit_text("Video bulunamadı. Biraz sonra tekrar dene.")
        return

    try:
        file_size = os.path.getsize(file_path)
        if file_size > 49 * 1024 * 1024:
            await status_msg.edit_text("Video çok büyük, başka bir tane arıyorum...")
            os.remove(file_path)
            return await send_random_video(query_list, chat_id, context, category)

        with open(file_path, "rb") as video:
            await context.bot.send_video(
                chat_id=chat_id,
                video=video,
                caption=f"📁 {category.upper()}",
                supports_streaming=True,
                reply_markup=get_keyboard()
            )
        await status_msg.delete()
    except Exception as e:
        await status_msg.edit_text(f"Gönderim hatası: {str(e)[:100]}")
    finally:
        try:
            os.remove(file_path)
        except:
            pass

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    if query.from_user.id != ADMIN_ID:
        await query.edit_message_text("Bu bot sadece sahibi tarafından kullanılabilir.")
        return

    data = query.data
    if not data.startswith("cat_"):
        return

    category = data[4:]
    queries = SEARCH_QUERIES.get(category)
    if not queries:
        return

    try:
        await query.message.delete()
    except:
        pass

    await send_random_video(queries, query.message.chat_id, context, category)

def main():
    if not BOT_TOKEN:
        print("BOT_TOKEN environment variable eksik!")
        return

    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_handler))
    print("Bot başlatıldı...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
