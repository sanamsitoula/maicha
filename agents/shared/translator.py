"""
Translator — uses TranslateGemma for Nepali translation
and supports other language pairs via Ollama models.
"""
import os
from agents.shared.ollama_client import chat

TRANSLATE_MODEL = os.getenv("TRANSLATE_MODEL", "qwen3:8b")


def translate_to_nepali(text, model=None):
    """Translate English text to Nepali using TranslateGemma."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": "You are a translator. Translate the following English text to Nepali. Output ONLY the Nepali translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "language": "ne", "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e), "original": text}


def translate_to_english(text, model=None):
    """Translate Nepali text to English using TranslateGemma."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": "You are a translator. Translate the following Nepali text to English. Output ONLY the English translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "language": "en", "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e), "original": text}


def translate(text, source_lang="en", target_lang="ne", model=None):
    """General translation between any supported languages."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": f"You are a translator. Translate the following {source_lang} text to {target_lang}. Output ONLY the translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "source": source_lang, "target": target_lang, "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def generate_nepali_content(topic, content_type="post", platform="facebook", model=None):
    """Generate content directly in Nepali.

    Two-step process:
    1. Generate content in English using the default LLM
    2. Translate to Nepali using TranslateGemma
    """
    from agents.shared.ollama_client import generate

    english_prompt = f"Write a {content_type} for {platform} about: {topic}. Be engaging and include relevant hashtags."
    english_content = generate(english_prompt, temperature=0.8)

    nepali_result = translate_to_nepali(english_content, model=model)

    return {
        "status": "ok",
        "topic": topic,
        "platform": platform,
        "content_type": content_type,
        "english": english_content,
        "nepali": nepali_result.get("translated", "Translation failed"),
        "translate_model": model or TRANSLATE_MODEL,
    }
