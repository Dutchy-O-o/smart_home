#!/usr/bin/env bash
# One-shot RFID DB migration: create authorized_cards + access_log tables.
# Idempotent — safe to re-run.

set -euo pipefail

REGION="us-east-1"
TMP_FN="oneshot-rfid-migrate-$(date +%s)"
SOURCE_PY="backend/_rfid_migrate.py"
REFERENCE_FN="UpdateActuatorState"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$SOURCE_PY" "$WORK_DIR/lambda_function.py"
WIN_SRC=$(cygpath -w "$WORK_DIR" 2>/dev/null || echo "$WORK_DIR")
WIN_OUT=$(cygpath -w "$WORK_DIR/code.zip" 2>/dev/null || echo "$WORK_DIR/code.zip")
python -c "
import os, zipfile, sys
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src, 'lambda_function.py'), 'lambda_function.py')
" "$WIN_SRC" "$WIN_OUT"

ROLE=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Role' --output text)
LAYERS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Layers[].Arn' --output text)
SUBNETS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SubnetIds' --output text | tr '\t' ',')
SGS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SecurityGroupIds' --output text | tr '\t' ',')
ENV_JSON=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Environment' --output json)
ENV_FILE="$WORK_DIR/env.json"
echo "$ENV_JSON" > "$ENV_FILE"
WIN_ENV=$(cygpath -w "$ENV_FILE" 2>/dev/null || echo "$ENV_FILE")

aws lambda create-function \
  --function-name "$TMP_FN" \
  --runtime python3.12 \
  --role "$ROLE" \
  --handler lambda_function.lambda_handler \
  --zip-file "fileb://$WIN_OUT" \
  --timeout 30 \
  --memory-size 256 \
  --layers $LAYERS \
  --vpc-config "SubnetIds=$SUBNETS,SecurityGroupIds=$SGS" \
  --environment "file://$WIN_ENV" \
  --region "$REGION" >/dev/null

aws lambda wait function-active --function-name "$TMP_FN" --region "$REGION"

RESULT_FILE="$WORK_DIR/result.json"
WIN_RESULT=$(cygpath -w "$RESULT_FILE" 2>/dev/null || echo "$RESULT_FILE")
aws lambda invoke \
  --function-name "$TMP_FN" \
  --region "$REGION" \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' \
  "$WIN_RESULT" >/dev/null

python -c "
import json, sys
with open(sys.argv[1], 'rb') as f:
    print(json.dumps(json.loads(f.read()), indent=2))
" "$WIN_RESULT"

aws lambda delete-function --function-name "$TMP_FN" --region "$REGION"
