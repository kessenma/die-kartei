// litertlm_runner — run the grammar eval prompts through a .litertlm bundle via the
// LiteRT-LM C API (libCLiteRTLM_mac.dylib), one fresh conversation per item.
//
// Exists because the released litert_lm_main CLI binaries (v0.11.0 linux/macos and
// v0.14.0 macos) ship without their Bazel runfiles shared libs
// (libGemmaModelConstraintProvider, libLiteRt) and won't load at all. The C API dylib in
// CLiteRTLM_mac.xcframework IS self-contained, so we drive it directly. This is also the
// same API path the iOS app would use, so it de-risks integration.
//
// Hard-won API notes (v0.14.0, verified against the official litert-community bundle):
//   * The low-level session path (generate_content / run_prefill+run_decode) returns a
//     response object with 1 candidate whose text is ALWAYS EMPTY. Only the Conversation
//     API actually yields generated text. Use it.
//   * litert_lm_conversation_config_set_system_message takes a PLAIN STRING, not JSON.
//     Passing {"role":"system","content":...} is silently ignored (no error, no effect).
//   * Sampler params are unreliable here: kLiteRtLmSamplerTypeTopK(1) returns
//     "UNIMPLEMENTED: Sampler type: 1 not implemented yet", and attaching sampler params
//     to a conversation's session config can make send_message return NULL. The DEFAULT
//     (no sampler params) verified deterministic across repeated runs, so we use it and
//     re-check determinism on the real suite.
//
// Wire format, NUL-delimited so UTF-8 and newlines need no escaping:
//   in:  <id>\0<max_output_tokens>\0<system_text>\0<user_message_json>\0   (repeated)
//   out: <id>\0<raw_response_json>\0                                      (repeated)
// The raw response JSON is parsed on the Python side rather than in C.
//
// Build:
//   clang -O2 -o litertlm_runner litertlm_runner.c -I<headers> -L<dylib dir> -lCLiteRTLM_mac
// Run:
//   ./litertlm_runner <model.litertlm> <backend:cpu|gpu> <in.bin> <out.bin>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include "engine.h"

static char *slurp(const char *path, size_t *out_len) {
  FILE *f = fopen(path, "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *buf = (char *)malloc((size_t)n + 1);
  if (!buf) { fclose(f); return NULL; }
  if (fread(buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(buf); return NULL; }
  fclose(f);
  buf[n] = '\0';
  *out_len = (size_t)n;
  return buf;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: %s <model.litertlm> <cpu|gpu> <in.bin> <out.bin>\n", argv[0]);
    return 2;
  }
  const char *model_path = argv[1];
  const char *backend = argv[2];

  litert_lm_set_min_log_level(3);  // WARNING+; keep stdout clean for progress lines

  size_t len = 0;
  char *blob = slurp(argv[3], &len);
  if (!blob) return 1;

  FILE *out = fopen(argv[4], "wb");
  if (!out) { fprintf(stderr, "cannot write %s\n", argv[4]); return 1; }

  fprintf(stderr, "loading %s (backend=%s) ...\n", model_path, backend);
  LiteRtLmEngineSettings *settings =
      litert_lm_engine_settings_create(model_path, backend, NULL, NULL);
  if (!settings) { fprintf(stderr, "FATAL: engine_settings_create returned NULL\n"); return 1; }

  LiteRtLmEngine *engine = litert_lm_engine_create(settings);
  if (!engine) {
    fprintf(stderr, "FATAL: engine_create returned NULL (bundle unreadable or backend unsupported)\n");
    litert_lm_engine_settings_delete(settings);
    return 1;
  }
  fprintf(stderr, "engine ready\n");

  size_t pos = 0;
  int n_done = 0, n_fail = 0;
  time_t t0 = time(NULL);
  while (pos < len) {
    const char *id = blob + pos;              pos += strlen(id) + 1;        if (pos >= len) break;
    const char *max_tok_s = blob + pos;       pos += strlen(max_tok_s) + 1; if (pos >= len) break;
    const char *system_text = blob + pos;     pos += strlen(system_text) + 1; if (pos > len) break;
    const char *user_json = blob + pos;       pos += strlen(user_json) + 1;

    int max_tokens = atoi(max_tok_s);

    LiteRtLmConversationConfig *ccfg = litert_lm_conversation_config_create();
    LiteRtLmSessionConfig *scfg = litert_lm_session_config_create();
    litert_lm_session_config_set_max_output_tokens(scfg, max_tokens);
    litert_lm_conversation_config_set_session_config(ccfg, scfg);
    if (system_text[0] != '\0') {
      litert_lm_conversation_config_set_system_message(ccfg, system_text);  // PLAIN string
    }

    // Fresh conversation per item so no KV/history state leaks between eval items.
    LiteRtLmConversation *cv = litert_lm_conversation_create(engine, ccfg);
    const char *json = NULL;
    LiteRtLmJsonResponse *jr = NULL;
    if (cv) {
      jr = litert_lm_conversation_send_message(cv, user_json, NULL, NULL);
      if (jr) json = litert_lm_json_response_get_string(jr);
    }
    if (!json) { json = ""; n_fail++; }

    fwrite(id, 1, strlen(id) + 1, out);
    fwrite(json, 1, strlen(json) + 1, out);
    fflush(out);  // partial progress survives a crash

    printf("[%d] %s: %.80s\n", ++n_done, id, json);
    fflush(stdout);

    if (jr) litert_lm_json_response_delete(jr);
    if (cv) litert_lm_conversation_delete(cv);
    litert_lm_session_config_delete(scfg);
    litert_lm_conversation_config_delete(ccfg);
  }

  fprintf(stderr, "done: %d items, %d empty, %lds elapsed\n",
          n_done, n_fail, (long)(time(NULL) - t0));
  litert_lm_engine_delete(engine);
  litert_lm_engine_settings_delete(settings);
  fclose(out);
  free(blob);
  return (n_done > 0 && n_fail == n_done) ? 1 : 0;  // all-empty is a failure, not a pass
}
