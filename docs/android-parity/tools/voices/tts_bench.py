"""Supertonic 3 (sherpa-onnx, int8) as the tutor would use it: load once, speak replies.

usage: tts_bench.py THREADS SECONDS   -> loops synthesis for SECONDS, prints per-utterance RTF
"""
import json, os, sys, time
import sherpa_onnx

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, "sherpa", "sherpa-onnx-supertonic-3-tts-int8-2026-05-11")
# A typical tutor turn: a short correction line plus a two-sentence reply.
REPLY = ["Fast richtig: Es heißt „mit dem Zug“, weil „mit“ immer den Dativ will.",
         "Und wohin bist du am Wochenende gefahren?",
         "Ich war letzten Sommer auch in Hamburg, die Stadt ist wirklich schön."]

threads, seconds = int(sys.argv[1]), float(sys.argv[2])
t0 = time.time()
tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
    supertonic=sherpa_onnx.OfflineTtsSupertonicModelConfig(
        duration_predictor=f"{D}/duration_predictor.int8.onnx", text_encoder=f"{D}/text_encoder.int8.onnx",
        vector_estimator=f"{D}/vector_estimator.int8.onnx", vocoder=f"{D}/vocoder.int8.onnx",
        tts_json=f"{D}/tts.json", unicode_indexer=f"{D}/unicode_indexer.bin", voice_style=f"{D}/voice.bin"),
    num_threads=threads, provider="cpu")))
load_s = time.time() - t0
g = sherpa_onnx.GenerationConfig(); g.sid = 3; g.num_steps = 8; g.speed = 1.0; g.extra["lang"] = "de"
runs, end = [], time.time() + seconds
while time.time() < end or not runs:
    for s in REPLY:
        t = time.time(); a = tts.generate(s, g); dt = time.time() - t
        runs.append(dict(gen_s=round(dt, 3), audio_s=round(len(a.samples) / a.sample_rate, 2)))
rtf = [r["gen_s"] / r["audio_s"] for r in runs]
print(json.dumps(dict(threads=threads, load_s=round(load_s, 2), n=len(runs),
                      first_sentence_s=runs[0]["gen_s"], rtf_median=round(sorted(rtf)[len(rtf) // 2], 3),
                      rtf_max=round(max(rtf), 3))))
