#!/usr/bin/env python3
"""Run the standard grammar eval against ELMOD-2.7B with a faithful GPT-NeoX activation.

WHY THIS WRAPPER EXISTS
-----------------------
`mlx_lm/models/gpt_neox.py`'s MLP hardcodes `nn.gelu_approx` (the tanh/FastGELU
approximation). ELMOD's `config.json` declares `hidden_act: "gelu"`, which HF's
`GPTNeoXMLP` resolves through `ACT2FN` to the exact erf-based `GELUActivation`.

That is not a harmless rounding difference. Measured on the 4-bit conversion, greedy
decoding of a single eval prompt diverges at **token 20 of 40** between the two
activations. Running the stock harness would have measured mlx_lm's approximation of
ELMOD rather than ELMOD, and the failure mode is fluent-but-different text — nothing
crashes and nothing looks wrong. (data/german-first-models-writeups/elmod.md §4 trap 4 predicted exactly this
shape for `attention_bias` / `use_parallel_residual`; both of those turned out fine and
the activation was the one that actually bit.)

The patch is scoped to `gpt_neox.MLP.__call__`, so no other architecture on the
scoreboard is affected and every other row stays comparable.

Usage (from training/) — takes all of run_baseline_eval.py's flags:
  .venv/bin/python scripts/eval_elmod.py --model models/elmod-2.7b-it-4bit \
      --tag baseline --app-guard
  .venv/bin/python scripts/eval_elmod.py --model models/elmod-2.7b-it-4bit \
      --tag baseline-extra --app-guard --eval-file data/eval/grammar_eval_v1_extra.json
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# mlx-lm 0.31.3 crashes importing under transformers 5.x while registering its
# "NewlineTokenizer". Same non-fatal shim run_baseline_eval.py uses.
from transformers import AutoTokenizer

_orig_register = AutoTokenizer.register


def _safe_register(*a, **k):
    try:
        _orig_register(*a, **k)
    except Exception:
        pass


AutoTokenizer.register = _safe_register

import mlx.nn as nn
from mlx_lm.models import gpt_neox


def _exact_gelu_mlp(self, x):
    """GPT-NeoX MLP with exact GELU, matching hidden_act: "gelu"."""
    return self.dense_4h_to_h(nn.gelu(self.dense_h_to_4h(x)))


gpt_neox.MLP.__call__ = _exact_gelu_mlp
print("[eval_elmod] patched gpt_neox.MLP to exact gelu (config hidden_act='gelu')")

import run_baseline_eval  # noqa: E402

if __name__ == "__main__":
    run_baseline_eval.main()
