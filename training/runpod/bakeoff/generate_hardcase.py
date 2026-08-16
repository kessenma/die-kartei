#!/usr/bin/env python3
"""Teacher bake-off: can this model construct HARD German learner errors on demand?

The question is narrow and specific. `gemma-4-26B-A4B-it` was asked, by name, for
"fehlendes oder falsches Reflexivpronomen (auch Akkusativ statt Dativ)" and produced the
accusative/dative case error 12% of the time, defaulting to trivial "missing sich". It was asked
for prefix mechanics and returned 26% plain word-order drill. Both batches were valid German and
passed every existing gate. The models trained on them scored 42-46/60 against v1's 54/60.

So this script does NOT measure fluency, JSON compliance, or throughput. It measures whether a
teacher can produce the specific hard error type when explicitly asked, scored by
`scripts/check_hard_case_share.py`:

    refl case-change share  >= 60%     (Sonnet: 65-100%,  gemma-26B: 12%)
    sep pure-reorder share  <=  5%     (Sonnet: 0%,       gemma-26B: 26%)

The prompts below are deliberately the SAME ones given to Claude Sonnet, including the worked
examples and the self-check instruction. That makes this a test of capability, not of prompt
quality — the v2 prompt already asked for the right thing and still failed.

Usage:
    python generate_hardcase.py --model <hf-id> --out out.jsonl [--per-phen 25] [--load-8bit]
"""
import argparse
import json
import re
import sys

REFL_SYS = """Du erstellst Trainingsdaten für einen deutschen Grammatik-Korrektur-Assistenten.

Erzeuge Sätze eines Deutschlerners mit einem REFLEXIVPRONOMEN-FEHLER und die Korrektur.

ENTSCHEIDENDE REGEL: Der Satz des Lerners MUSS BEREITS ein Reflexivpronomen enthalten, und die \
Korrektur MUSS dieses Pronomen ÄNDERN. Niemals nur ein fehlendes Pronomen EINFÜGEN.

RICHTIG (Kasus geändert, mich -> mir):
  student: "Ich wasche mich die Hände."      fix: "Ich wasche mir die Hände."
RICHTIG (Person geändert, sich -> uns):
  student: "Wir treffen sich morgen."        fix: "Wir treffen uns morgen."
FALSCH (nur eingefügt — VERBOTEN in dieser Aufgabe):
  student: "Ich interessiere für Musik."     fix: "Ich interessiere mich für Musik."

Selbstprüfung für JEDE Zeile: die Menge aus {mich, mir, dich, dir, sich, uns, euch} im "student" \
und im "fix" muss BEIDE nicht leer und VERSCHIEDEN sein.

Nutze Dativ-Reflexiva ("sich etwas anschauen/wünschen/notieren/leisten/merken/kaufen/gönnen", \
"sich die Zähne putzen", "sich die Hände waschen") und Personenfehler \
("sich treffen/erinnern/erholen/beeilen/verabreden").

Antworte NUR mit JSONL, eine Zeile pro Beispiel, kein Markdown, keine Erklärung:
{"task":"correction","phenomenon":"refl","level":"A2"|"B1"|"B2","formality":"du"|"Sie",\
"partner":null,"student":"...","verdict":"fix","fix":"...","why":"<kurze englische Regel>",\
"meta":{"verb":"sich anschauen"}}"""

SEP_SYS = """Du erstellst Trainingsdaten für einen deutschen Grammatik-Korrektur-Assistenten.

Erzeuge Sätze eines Deutschlerners mit einem Fehler bei der MORPHOLOGIE trennbarer/untrennbarer \
Verben und die Korrektur.

ENTSCHEIDENDE REGEL: Der Fehler MUSS in der VERBFORM liegen — Präfix falsch angehängt, falsch \
abgetrennt, oder Partizip falsch gebildet. NIEMALS eine reine Umstellung anderer Satzglieder.

Selbstprüfung für JEDE Zeile: sortiert(Wörter von "student") darf NICHT gleich \
sortiert(Wörter von "fix") sein. Wenn die Korrektur nur vorhandene Wörter VERSCHIEBT, ist die \
Zeile falsch.

RICHTIG (Morphologie):
  student: "Ich aufstehe jeden Tag um sieben."   fix: "Ich stehe jeden Tag um sieben auf."
  student: "Er hat das Licht ausmachen."         fix: "Er hat das Licht ausgemacht."
  student: "Wir haben den Stau gevermieden."     fix: "Wir haben den Stau vermieden."
FALSCH (nur verschoben — VERBOTEN):
  student: "Du machst das Licht aus im Zimmer."  fix: "Du machst das Licht im Zimmer aus."
FALSCH (V2-Inversion, falsches Phänomen — VERBOTEN):
  student: "Warum du rufst mich an?"             fix: "Warum rufst du mich an?"

Nutze trennbare Verben (aufstehen, anrufen, ausmachen, einkaufen, abholen, ankommen, einladen, \
aufräumen, mitbringen, anfangen) und untrennbare (vermeiden, verstehen, bekommen, erklären, \
übersetzen, besuchen, bezahlen) für Partizipien ohne -ge-.

Antworte NUR mit JSONL, eine Zeile pro Beispiel, kein Markdown, keine Erklärung:
{"task":"correction","phenomenon":"sep","level":"A2"|"B1"|"B2","formality":"du"|"Sie",\
"partner":null,"student":"...","verdict":"fix","fix":"...","why":"<kurze englische Regel>",\
"meta":{"verb":"aufstehen","subtype":"attached"|"separated"}}"""

USER_TMPL = "Erzeuge {n} verschiedene Beispiele. Variiere Subjekt, Zeitform, Länge und Thema."

# Anchored to key position. The v2 bug (§1.5b) used an UNANCHORED version of this, which rewrote
# `"verdict":"fix","fix":"..."` into invalid JSON and silently destroyed every correction row.
_DUP_KEY_RE = re.compile(r'([,{])\s*"(\w+)"\s*,\s*"\2"\s*:')


def repair(line: str) -> str:
    return _DUP_KEY_RE.sub(r'\1"\2":', line)


def parse_rows(text: str) -> list:
    """Teachers emit bare JSONL, ```json fences, preambles, or pretty-printed objects."""
    rows = []
    text = re.sub(r"```(?:json|jsonl)?", "", text)
    for line in text.splitlines():
        line = line.strip().rstrip(",")
        if not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(repair(line)))
        except json.JSONDecodeError:
            continue
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-phen", type=int, default=25)
    ap.add_argument("--batch", type=int, default=10, help="examples requested per call")
    ap.add_argument("--load-8bit", action="store_true")
    ap.add_argument("--max-new-tokens", type=int, default=2048)
    args = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    print(f"loading {args.model} ...", flush=True)
    tok = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    kw = {"trust_remote_code": True, "device_map": "auto", "dtype": torch.bfloat16}
    if args.load_8bit:
        from transformers import BitsAndBytesConfig
        kw["quantization_config"] = BitsAndBytesConfig(load_in_8bit=True)
        kw.pop("dtype")
    model = AutoModelForCausalLM.from_pretrained(args.model, **kw)
    model.eval()
    print("loaded.", flush=True)

    out = []
    for phen, sys_prompt in (("refl", REFL_SYS), ("sep", SEP_SYS)):
        got = []
        attempts = 0
        while len(got) < args.per_phen and attempts < 8:
            attempts += 1
            msgs = [{"role": "system", "content": sys_prompt},
                    {"role": "user", "content": USER_TMPL.format(n=args.batch)}]
            # `enable_thinking=False` is NOT optional for Qwen3.x. Its template defaults to
            # "Reasoning effort is set to xhigh" and opens a <think> block, which eats the entire
            # max_new_tokens budget before any JSON is emitted — the model looks like it produced
            # nothing. `run_baseline_eval.py` already passes this flag for the same reason.
            # Templates that don't accept the kwarg raise TypeError and fall through.
            def build(messages):
                try:
                    return tok.apply_chat_template(messages, add_generation_prompt=True,
                                                   tokenize=False, enable_thinking=False)
                except TypeError:
                    return tok.apply_chat_template(messages, add_generation_prompt=True,
                                                   tokenize=False)

            try:
                prompt = build(msgs)
            except Exception:  # no system role in this template
                prompt = build([{"role": "user", "content": sys_prompt + "\n\n" +
                                 USER_TMPL.format(n=args.batch)}])
            enc = tok(prompt, return_tensors="pt").to(model.device)
            with torch.no_grad():
                gen = model.generate(**enc, max_new_tokens=args.max_new_tokens,
                                     do_sample=True, temperature=0.8, top_p=0.95,
                                     pad_token_id=tok.eos_token_id)
            text = tok.decode(gen[0][enc["input_ids"].shape[1]:], skip_special_tokens=True)
            rows = [r for r in parse_rows(text)
                    if r.get("phenomenon") == phen and r.get("student") and r.get("fix")]
            got.extend(rows)
            print(f"  {phen}: attempt {attempts} -> +{len(rows)} (total {len(got)})", flush=True)
        out.extend(got[:args.per_phen])

    with open(args.out, "w") as fh:
        for r in out:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(out)} rows to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
