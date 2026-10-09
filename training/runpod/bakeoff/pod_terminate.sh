#!/bin/bash
# pod_terminate.sh — remove the pod this runs on. Called by kasus_bakeoff.sh once the upload is
# verified, and by the deadline backstop:
#   setsid nohup bash -c "sleep 14400; bash /workspace/pod_terminate.sh deadline" \
#     > /workspace/deadline.log 2>&1 < /dev/null &
#
# Reads SELF_POD_ID and RUNPOD_API_KEY (a RESTRICTED key) from /workspace/.env.run, written over
# SSH with mode 600 rather than set as pod env, so the key isn't stored in the pod's config.
# GraphQL's podTerminate first, since it doesn't depend on which runpodctl the image ships;
# runpodctl a minute later if the pod is somehow still alive.
[ -f /workspace/.env.run ] && { set -a; . /workspace/.env.run; set +a; }
# /workspace/HOLD keeps the pod for follow-up work after the main run; the deadline ignores it.
if [ -f /workspace/HOLD ] && [ "${1:-}" != "deadline" ]; then
  echo "$(date -u +%FT%TZ) HOLD present — not terminating (${1:-})"
  exit 0
fi
if [ -z "${SELF_POD_ID:-}" ] || [ -z "${RUNPOD_API_KEY:-}" ]; then
  echo "SELF_POD_ID/RUNPOD_API_KEY not set — CANNOT SELF-TERMINATE. POD STILL BILLING."
  exit 1
fi
echo "$(date -u +%FT%TZ) terminating pod $SELF_POD_ID (${1:-})"
curl -s -m 30 -X POST https://api.runpod.io/graphql \
  -H "Content-Type: application/json" -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d "{\"query\":\"mutation { podTerminate(input: {podId: \\\"$SELF_POD_ID\\\"}) }\"}"
echo
sleep 60
runpodctl config --apiKey "$RUNPOD_API_KEY" > /dev/null 2>&1
runpodctl remove pod "$SELF_POD_ID" || runpodctl pod delete "$SELF_POD_ID"
