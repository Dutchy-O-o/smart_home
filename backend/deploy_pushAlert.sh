#!/usr/bin/env bash
# Deploy pushAlertNotificationstoUsers Lambda by swapping ONLY the .py file
# inside the existing deployment package (preserves firebase-service-account.json).
# Run from repo root.

set -euo pipefail

FUNCTION_NAME="pushAlertNotificationstoUsers"
REGION="us-east-1"
SOURCE_PY="backend/pushAlertNotificationtoUser.py"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Working dir: $WORK_DIR"

# 1. Download current deployment package
echo "==> Downloading current deployment package..."
URL=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Code.Location' --output text)
curl -s -o "$WORK_DIR/current.zip" "$URL"

# 2. Backup the current zip locally (so you can roll back fast)
BACKUP="backend/_lambda_backup_$(date +%Y%m%d_%H%M%S).zip"
cp "$WORK_DIR/current.zip" "$BACKUP"
echo "==> Backup saved to $BACKUP"

# 3. Unpack, list, sanity-check that the expected files exist
mkdir -p "$WORK_DIR/pkg"
unzip -q -o "$WORK_DIR/current.zip" -d "$WORK_DIR/pkg"

if [ ! -f "$WORK_DIR/pkg/firebase-service-account.json" ]; then
  echo "ERROR: firebase-service-account.json missing from existing package — aborting."
  echo "       (Re-deploying without it would break Firebase init.)"
  exit 1
fi

# 4. Swap in the new code under the handler name Lambda expects
cp "$SOURCE_PY" "$WORK_DIR/pkg/lambda_function.py"
echo "==> Replaced lambda_function.py"

# 5. Re-zip (use Python so we don't depend on the `zip` binary, which is
# missing from git-bash on Windows). Convert paths to native Windows form
# because Python on Windows doesn't understand MSYS /tmp/... paths.
WIN_SRC=$(cygpath -w "$WORK_DIR/pkg" 2>/dev/null || echo "$WORK_DIR/pkg")
WIN_OUT=$(cygpath -w "$WORK_DIR/new.zip" 2>/dev/null || echo "$WORK_DIR/new.zip")
python -c "
import os, zipfile, sys
src = sys.argv[1]
out = sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
print('zipped:', out)
" "$WIN_SRC" "$WIN_OUT"

# 6. Upload (use Windows-style path because AWS CLI on Windows doesn't
# understand MSYS /tmp/... paths)
echo "==> Uploading to Lambda..."
UPLOAD_PATH="$WIN_OUT"
aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file "fileb://$UPLOAD_PATH" \
  --region "$REGION" \
  --query '{Version:Version,LastModified:LastModified,CodeSize:CodeSize}' \
  --output table

echo "==> Done. To roll back: aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://$BACKUP --region $REGION"
