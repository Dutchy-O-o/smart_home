#!/usr/bin/env bash
# Create the verifyRfidAccess Lambda + IoT Rule + Lambda invoke permission.
# Idempotent: re-running will report "already exists" but won't break anything.

set -euo pipefail

REGION="us-east-1"
ACCOUNT="162803876446"
FUNCTION_NAME="verifyRfidAccess"
RULE_NAME="rfidAccessCheck"
SOURCE_PY="backend/verifyRfidAccess.py"
REFERENCE_FN="UpdateActuatorState"   # we copy its role/VPC/layers/env
IOT_ENDPOINT="a1cxjn3ytw2lp0-ats.iot.us-east-1.amazonaws.com"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> 1. Build deployment zip"
cp "$SOURCE_PY" "$WORK_DIR/lambda_function.py"
WIN_SRC=$(cygpath -w "$WORK_DIR" 2>/dev/null || echo "$WORK_DIR")
WIN_OUT=$(cygpath -w "$WORK_DIR/code.zip" 2>/dev/null || echo "$WORK_DIR/code.zip")
python -c "
import os, zipfile, sys
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src, 'lambda_function.py'), 'lambda_function.py')
" "$WIN_SRC" "$WIN_OUT"

echo "==> 2. Pull config from $REFERENCE_FN"
ROLE=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Role' --output text)
LAYERS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Layers[].Arn' --output text)
SUBNETS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SubnetIds' --output text | tr '\t' ',')
SGS=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'VpcConfig.SecurityGroupIds' --output text | tr '\t' ',')
REF_ENV_JSON=$(aws lambda get-function-configuration --function-name "$REFERENCE_FN" --region "$REGION" --query 'Environment.Variables' --output json)

# Add IOT_ENDPOINT to the env JSON (new lambda needs it)
ENV_FILE="$WORK_DIR/env.json"
python -c "
import json, sys
ref = json.loads(sys.argv[1])
ref['IOT_ENDPOINT'] = '$IOT_ENDPOINT'
print(json.dumps({'Variables': ref}))
" "$REF_ENV_JSON" > "$ENV_FILE"
WIN_ENV=$(cygpath -w "$ENV_FILE" 2>/dev/null || echo "$ENV_FILE")

echo "==> 3. Create or update Lambda"
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "   Function exists — updating code"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$WIN_OUT" \
    --region "$REGION" \
    --query 'LastModified' --output text
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$REGION"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "file://$WIN_ENV" \
    --region "$REGION" >/dev/null
else
  echo "   Function does not exist — creating"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --role "$ROLE" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$WIN_OUT" \
    --timeout 10 \
    --memory-size 128 \
    --layers $LAYERS \
    --vpc-config "SubnetIds=$SUBNETS,SecurityGroupIds=$SGS" \
    --environment "file://$WIN_ENV" \
    --region "$REGION" \
    --query '{FunctionName:FunctionName,State:State}' --output table
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$REGION"
fi

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FUNCTION_NAME}"
echo "   Lambda ARN: $LAMBDA_ARN"

echo "==> 4. Create IoT topic rule (or skip if exists)"
if aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "   Rule $RULE_NAME already exists — leaving as is"
else
  RULE_PAYLOAD=$(cat <<EOF
{
  "sql": "SELECT * FROM 'homes/+/rfid_check'",
  "ruleDisabled": false,
  "actions": [
    {
      "lambda": {
        "functionArn": "$LAMBDA_ARN"
      }
    }
  ]
}
EOF
)
  echo "$RULE_PAYLOAD" > "$WORK_DIR/rule.json"
  WIN_RULE=$(cygpath -w "$WORK_DIR/rule.json" 2>/dev/null || echo "$WORK_DIR/rule.json")
  aws iot create-topic-rule \
    --rule-name "$RULE_NAME" \
    --topic-rule-payload "file://$WIN_RULE" \
    --region "$REGION"
  echo "   Rule created"
fi

echo "==> 5. Allow IoT to invoke the Lambda"
STATEMENT_ID="rfidAccessCheck-iot-invoke"
if aws lambda get-policy --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Policy' --output text 2>/dev/null | grep -q "$STATEMENT_ID"; then
  echo "   Permission already exists — skipping"
else
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id "$STATEMENT_ID" \
    --action 'lambda:InvokeFunction' \
    --principal 'iot.amazonaws.com' \
    --source-arn "arn:aws:iot:${REGION}:${ACCOUNT}:rule/${RULE_NAME}" \
    --region "$REGION" \
    --query 'Statement' --output text
fi

echo
echo "==> Done."
echo "   Function: $FUNCTION_NAME"
echo "   Rule:     $RULE_NAME (topic: homes/+/rfid_check)"
echo "   Endpoint env: IOT_ENDPOINT=$IOT_ENDPOINT"
