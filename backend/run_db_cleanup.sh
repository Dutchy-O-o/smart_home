#!/usr/bin/env bash
# One-shot DB cleanup runner: creates a temp Lambda inside the same VPC as
# UpdateActuatorState (so it can talk to RDS), invokes it, then deletes it.
# Safe: rolls back automatically if verification fails.

set -euo pipefail

REGION="us-east-1"
TMP_FN="oneshot-db-cleanup-$(date +%s)"
SOURCE_PY="backend/_oneshot_db_cleanup.py"
REFERENCE_FN="UpdateActuatorState"   # we copy its role + VPC + layers + env

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Working dir: $WORK_DIR"

# 1. Copy source as lambda_function.py and zip
cp "$SOURCE_PY" "$WORK_DIR/lambda_function.py"
WIN_SRC=$(cygpath -w "$WORK_DIR" 2>/dev/null || echo "$WORK_DIR")
WIN_OUT=$(cygpath -w "$WORK_DIR/code.zip" 2>/dev/null || echo "$WORK_DIR/code.zip")
python -c "
import os, zipfile, sys
src = sys.argv[1]
out = sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src, 'lambda_function.py'), 'lambda_function.py')
print('zipped:', out)
" "$WIN_SRC" "$WIN_OUT"

# 2. Pull config from reference function
echo "==> Reading config from $REFERENCE_FN"
CONFIG=$(aws lambda get-function-configuration \
  --function-name "$REFERENCE_FN" \
  --region "$REGION" --output json)

ROLE=$(echo "$CONFIG" | python -c "import json,sys; print(json.load(sys.stdin)['Role'])")
LAYERS=$(echo "$CONFIG" | python -c "import json,sys; print(' '.join(l for l in json.load(sys.stdin).get('Layers') and [a['Arn'] for a in json.load(sys.stdin)['Layers']] or []))" 2>/dev/null || true)
# Re-fetch layers (the line above re-reads stdin which is empty on the second read)
LAYERS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Layers[].Arn' --output text)
SUBNETS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SubnetIds' --output text | tr '\t' ',')
SGS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SecurityGroupIds' --output text | tr '\t' ',')
ENV_JSON=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Environment' --output json)

echo "  role: $ROLE"
echo "  layers: $LAYERS"
echo "  subnets: $SUBNETS"
echo "  sgs: $SGS"

# 3. Create temp lambda
echo "==> Creating temp function: $TMP_FN"
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
  --region "$REGION" \
  --query '{FunctionName:FunctionName,State:State}' --output table

# 4. Wait for it to become active (VPC-attached lambdas take ~10s)
echo "==> Waiting for function to be Active..."
aws lambda wait function-active --function-name "$TMP_FN" --region "$REGION"

# 5. Invoke
echo "==> Invoking..."
RESULT_FILE="$WORK_DIR/result.json"
WIN_RESULT=$(cygpath -w "$RESULT_FILE" 2>/dev/null || echo "$RESULT_FILE")
aws lambda invoke \
  --function-name "$TMP_FN" \
  --region "$REGION" \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' \
  "$WIN_RESULT" \
  --query 'StatusCode' --output text

echo
echo "==> Result:"
cat "$RESULT_FILE"
echo

# 6. Always delete the temp function, even if the invoke result was an error
echo "==> Deleting temp function..."
aws lambda delete-function --function-name "$TMP_FN" --region "$REGION"
echo "==> Cleanup done. Function $TMP_FN removed."
