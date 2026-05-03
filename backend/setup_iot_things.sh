#!/usr/bin/env bash
# Idempotently create IoT Things + initial Classic Shadows for TV / AC / Stove.
# Safe to re-run: existing Things are skipped; shadows are upserted.
#
# Usage:
#   ./backend/setup_iot_things.sh <HOME_ID> [REGION]
#
# Example:
#   ./backend/setup_iot_things.sh home_abc123
#   ./backend/setup_iot_things.sh home_abc123 us-east-1

set -euo pipefail

HOME_ID="${1:-}"
REGION="${2:-us-east-1}"

if [ -z "$HOME_ID" ]; then
  echo "ERROR: HOME_ID is required."
  echo "Usage: $0 <HOME_ID> [REGION]"
  exit 1
fi

# Validate HOME_ID shape (alphanumeric + underscore + dash only) — IoT Thing
# names must match [a-zA-Z0-9:_-]
if [[ ! "$HOME_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: HOME_ID '$HOME_ID' contains illegal characters. Use [a-zA-Z0-9_-]."
  exit 1
fi

echo "==> Region: $REGION"
echo "==> Home ID: $HOME_ID"
echo

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------- helpers ----------

ensure_thing() {
  local thing_name="$1"
  local thing_type="$2"  # informational only — used as a tag attribute

  if aws iot describe-thing \
       --thing-name "$thing_name" \
       --region "$REGION" >/dev/null 2>&1; then
    echo "  [skip] Thing already exists: $thing_name"
  else
    aws iot create-thing \
      --thing-name "$thing_name" \
      --attribute-payload "attributes={device_type=$thing_type,home_id=$HOME_ID}" \
      --region "$REGION" >/dev/null
    echo "  [ok]   Created thing: $thing_name"
  fi
}

# update-thing-shadow upserts: creates the shadow if it doesn't exist yet.
# Convert paths to native Windows form because AWS CLI on Windows does not
# understand MSYS /tmp/... style paths.
upsert_shadow() {
  local thing_name="$1"
  local payload_file="$2"
  local out_file="$WORK_DIR/${thing_name}.shadow.out"
  local win_payload
  local win_out
  win_payload=$(cygpath -w "$payload_file" 2>/dev/null || echo "$payload_file")
  win_out=$(cygpath -w "$out_file" 2>/dev/null || echo "$out_file")

  aws iot-data update-thing-shadow \
    --thing-name "$thing_name" \
    --region "$REGION" \
    --cli-binary-format raw-in-base64-out \
    --payload "file://$win_payload" \
    "$win_out" >/dev/null
  echo "  [ok]   Shadow initialized: $thing_name"
}

# ---------- TV ----------
TV_THING="tv_${HOME_ID}_living"
TV_PAYLOAD="$WORK_DIR/tv_shadow.json"
cat > "$TV_PAYLOAD" <<'EOF'
{
  "state": {
    "reported": {
      "power": "off",
      "volume": 30,
      "channel": 1,
      "source": "HDMI1"
    }
  }
}
EOF

# ---------- AC (Klima) ----------
AC_THING="ac_${HOME_ID}_living"
AC_PAYLOAD="$WORK_DIR/ac_shadow.json"
cat > "$AC_PAYLOAD" <<'EOF'
{
  "state": {
    "reported": {
      "power": "off",
      "temperature": 24,
      "mode": "cool",
      "fan_speed": "auto"
    }
  }
}
EOF

# ---------- Stove (Ocak) ----------
STOVE_THING="stove_${HOME_ID}_kitchen"
STOVE_PAYLOAD="$WORK_DIR/stove_shadow.json"
cat > "$STOVE_PAYLOAD" <<'EOF'
{
  "state": {
    "reported": {
      "power": "off",
      "heat_level": 0,
      "safety_lock": "on"
    }
  }
}
EOF

# ---------- run ----------
echo "==> [1/3] TV"
ensure_thing "$TV_THING" "tv"
upsert_shadow "$TV_THING" "$TV_PAYLOAD"
echo

echo "==> [2/3] AC (Klima)"
ensure_thing "$AC_THING" "ac"
upsert_shadow "$AC_THING" "$AC_PAYLOAD"
echo

echo "==> [3/3] Stove (Ocak)"
ensure_thing "$STOVE_THING" "stove"
upsert_shadow "$STOVE_THING" "$STOVE_PAYLOAD"
echo

# ---------- summary ----------
echo "==> Verification"
for t in "$TV_THING" "$AC_THING" "$STOVE_THING"; do
  verify_file="$WORK_DIR/${t}.verify"
  win_verify=$(cygpath -w "$verify_file" 2>/dev/null || echo "$verify_file")
  if aws iot-data get-thing-shadow \
       --thing-name "$t" \
       --region "$REGION" \
       "$win_verify" >/dev/null 2>&1; then
    STATE=$(python -c "
import sys, json
with open(sys.argv[1], 'rb') as f:
    d = json.loads(f.read())
print(json.dumps(d.get('state', {}).get('reported', {})))
" "$win_verify" 2>/dev/null || echo "<parse-error>")
  else
    STATE="<missing>"
  fi
  printf "  %-50s reported=%s\n" "$t" "$STATE"
done

echo
echo "==> Done."
echo "    Next: insert these device rows into Postgres so the mobile app picks them up."
echo "    Thing names to use as deviceid in the 'devices' table:"
echo "      - $TV_THING"
echo "      - $AC_THING"
echo "      - $STOVE_THING"
