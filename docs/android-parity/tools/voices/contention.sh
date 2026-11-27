#!/bin/bash
# Tutor (llama.cpp, Gemma 4 E2B Q4_K_M) and Supertonic at the same time, on this Mac's CPU.
cd "$(dirname "$0")"
L=~/ws/llama.cpp/build/bin/llama-bench
M=~/ws/models/release/e2b/gemma4-e2b-german-tutor-Q4_K_M.gguf
tps() { python3 -c "import json,sys; print(round(json.load(sys.stdin)[0]['avg_ts'],1))"; }
echo "llm alone cpu t4: $($L -m $M -ngl 0 -t 4 -p 0 -n 64 -r 3 -o json 2>/dev/null | tps) tok/s"
for t in 2 1; do
  .venv/bin/python tts_bench.py $t 25 > tts_conc_$t.json &
  sleep 1
  echo "llm cpu t4 with tts t$t: $($L -m $M -ngl 0 -t 4 -p 0 -n 64 -r 3 -o json 2>/dev/null | tps) tok/s"
  wait
  echo "tts t$t during llm: $(cat tts_conc_$t.json)"
done
echo "llm alone metal: $($L -m $M -ngl 99 -p 0 -n 64 -r 3 -o json 2>/dev/null | tps) tok/s"
.venv/bin/python tts_bench.py 2 25 > tts_conc_metal.json &
sleep 1
echo "llm metal with tts t2: $($L -m $M -ngl 99 -p 0 -n 64 -r 3 -o json 2>/dev/null | tps) tok/s"
wait
echo "tts t2 during metal llm: $(cat tts_conc_metal.json)"
