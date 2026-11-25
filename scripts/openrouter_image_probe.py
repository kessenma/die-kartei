#!/usr/bin/env python3
"""Probe OpenRouter's image models with the shapes the app will send (POST /api/v1/images — Muse is not served on chat/completions), before the Swift parser
is written against them.

For each model: one flashcard picture, one story picture, and the story's next picture with the
first one passed as a reference (does the model keep the characters?). Also captures the response
shapes of `GET /api/v1/key` and of a request made with a bad key — both free.

The key comes from $OPENROUTER_API_KEY, else from the main checkout's gitignored .env. It is never
written anywhere: saved JSON has the base64 cut down and no headers.

    python3 scripts/openrouter_image_probe.py [out_dir] [model-filter, e.g. muse]
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://openrouter.ai/api/v1"
ENV_FALLBACK = "/Users/ke/ws/german-flashcards/german-ai-flashcards/.env"

# Extra body fields per model for POST /images. Muse advertises no parameters but honors
# aspect_ratio (1600² square; left alone it chose 1920×1280 for a story scene).
MODELS = {
    "meta/muse-image": {"aspect_ratio": "1:1"},
    "google/gemini-2.5-flash-image": {"aspect_ratio": "1:1"},
}

NO_TEXT = "No text, letters, numbers, labels or captions anywhere in the picture."
CARD = (
    "A simple flat vector illustration of a single membership card, for a vocabulary flashcard. "
    "Bold solid shapes, soft bright colors. One clear subject, centered on a plain empty background, "
    "square. " + NO_TEXT
)
STORY_STYLE = "Style: warm storybook illustration of everyday life, soft colors."
CAST = ("Characters: pigeon = plump gray pigeon with a white belly and a coral-orange beak; "
        "baker = young baker with curly red hair and a red apron.")
STORY_1 = ("Illustration for a short German story for language learners. Scene: a pigeon sits on the "
           "windowsill of a small bakery in the morning while the baker sets out fresh pretzels. "
           f"{CAST} {STORY_STYLE} {NO_TEXT}")
STORY_2 = ("Illustration for a short German story for language learners. Keep the characters and art "
           "style consistent with the reference picture. Scene: the baker chases the pigeon down a "
           f"cobblestone street, the pigeon holding a pretzel in its beak. {CAST} {STORY_STYLE} {NO_TEXT}")


def load_key():
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key.strip()
    with open(ENV_FALLBACK) as f:
        for line in f:
            if line.startswith("OPENROUTER_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("No OPENROUTER_API_KEY in the environment or " + ENV_FALLBACK)


def call(method, path, key, body=None, timeout=180):
    req = urllib.request.Request(API + path, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("HTTP-Referer", "https://kessenma.github.io/kartei-privacy")
    req.add_header("X-OpenRouter-Title", "Die Kartei")
    data = None
    if body is not None:
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
    start = time.time()
    try:
        with urllib.request.urlopen(req, data=data, timeout=timeout) as r:
            return r.status, json.loads(r.read()), time.time() - start
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw), time.time() - start
        except ValueError:
            return e.code, {"raw": raw.decode(errors="replace")[:500]}, time.time() - start


def redact(obj):
    """Cut base64 payloads down so the saved JSON shows the shape, not megabytes."""
    if isinstance(obj, dict):
        return {k: redact(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [redact(v) for v in obj]
    if isinstance(obj, str) and len(obj) > 200 and ("base64," in obj[:80] or obj[:4] in ("iVBO", "/9j/", "UklG")):
        return obj[:60] + f"…<{len(obj)} chars>"
    return obj


def images_in(resp):
    """`/images` answers {data:[{b64_json, media_type}]}; return them as data URLs."""
    urls = []
    for item in resp.get("data") or []:
        if item.get("b64_json"):
            urls.append(f"data:{item.get('media_type', 'image/png')};base64,{item['b64_json']}")
        elif item.get("url"):
            urls.append(item["url"])
    return urls


def decode(url):
    if url.startswith("data:"):
        header, b64 = url.split(",", 1)
        return header[5:].split(";")[0], base64.b64decode(b64)
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.headers.get_content_type(), r.read()


def image_size(data):
    try:
        from PIL import Image
        import io
        with Image.open(io.BytesIO(data)) as im:
            return f"{im.format} {im.width}x{im.height}"
    except Exception:
        return f"{len(data)} bytes"


def generate(key, model, prompt, reference=None):
    body = {"model": model, "prompt": prompt, "user": "kartei-probe", **MODELS[model]}
    if reference:
        body["input_references"] = [{"type": "image_url", "image_url": {"url": reference}}]
    return call("POST", "/images", key, body)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "openrouter-probe"
    os.makedirs(out, exist_ok=True)
    key = load_key()
    summary = []

    status, info, _ = call("GET", "/key", key)
    json.dump(redact(info), open(f"{out}/key-info.json", "w"), indent=2)
    print(f"GET /key → {status}: usage={info.get('data', {}).get('usage')} "
          f"limit_remaining={info.get('data', {}).get('limit_remaining')}")

    status, bad, _ = call("GET", "/key", "sk-or-v1-not-a-real-key")
    json.dump(bad, open(f"{out}/bad-key.json", "w"), indent=2)
    print(f"bad key → {status}: {bad}")

    only = sys.argv[2] if len(sys.argv) > 2 else None
    for model in MODELS:
        if only and only not in model:
            continue
        slug = model.split("/")[1]
        first_ref = None
        for name, prompt in (("card", CARD), ("story1", STORY_1), ("story2-ref", STORY_2)):
            ref = first_ref if name == "story2-ref" else None
            if name == "story2-ref" and not ref:
                print(f"{slug} {name}: skipped (no story1 picture)")
                continue
            status, resp, secs = generate(key, model, prompt, ref)
            json.dump(redact(resp), open(f"{out}/{slug}-{name}.json", "w"), indent=2)
            urls = images_in(resp)
            cost = (resp.get("usage") or {}).get("cost")
            line = f"{slug} {name}: HTTP {status} in {secs:.1f}s, {len(urls)} image(s), cost={cost}"
            if urls:
                mime, data = decode(urls[0])
                ext = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}.get(mime, "bin")
                path = f"{out}/{slug}-{name}.{ext}"
                open(path, "wb").write(data)
                line += f", {mime} {image_size(data)} → {path}"
                if name == "story1":
                    first_ref = urls[0]
            else:
                line += f", error={resp.get('error')}"
            print(line)
            summary.append(line)

    open(f"{out}/summary.txt", "w").write("\n".join(summary) + "\n")


if __name__ == "__main__":
    main()
