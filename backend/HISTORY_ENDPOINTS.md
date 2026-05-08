# History endpoints — deployment guide

These three Lambdas back the new "AWS-side history" features in the
Flutter app:

| File | Route | Purpose |
|------|-------|---------|
| `getMoodHistory.py` | `GET /{homeID}/emotion-history?days=7` | 7-day mood heatmap |
| `getSensorHistory.py` | `GET /{homeID}/sensor-history?hours=12` | dashboard sparkline |
| `saveAlertEvent.py` | `POST /{homeID}/alerts` + `GET /{homeID}/alerts` | cross-device notifications |

The Flutter side already calls these — when they 404 / 500 the app
falls back to the local SharedPreferences buffer, so deploying any
single one is non-breaking.

## Deploy steps (per Lambda)

1. **Create the function** in Lambda console
   - Runtime: Python 3.11 (or 3.12)
   - Architecture: x86_64
   - Permissions: reuse the same execution role as `getLatestEmotion`
     (it already has psycopg2 layer + RDS network reach)

2. **Attach the psycopg2 layer**
   - Use the existing layer the other Lambdas use. If you don't have
     it on hand, AWS provides one at
     `arn:aws:lambda:us-east-1:898466741470:layer:psycopg2-py311:1`
     (community-maintained, region-specific).

3. **Set environment variables** — same 4 the other RDS Lambdas use:
   ```
   DB_HOST=<rds endpoint>
   DB_NAME=<db>
   DB_USER=<user>
   DB_PASSWORD=<password>
   ```

4. **VPC config** — match `getLatestEmotion`'s VPC + subnets +
   security group so the function can actually reach RDS.

5. **API Gateway route**
   - Open the existing `prod` API
   - Add the resource path under the existing `{homeID}` parent
   - Method: `GET` (or `POST + GET` for alerts)
   - Integration: Lambda proxy → the function you just created
   - Authorization: the existing **Cognito User Pool authorizer**
   - Deploy the API to the `prod` stage

6. **Test in a browser console** with a fresh ID token:
   ```
   curl -H "Authorization: Bearer <id_token>" \
     'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/<homeID>/emotion-history?days=7'
   ```

## Schema for `saveAlertEvent`

The mood history and sensor history Lambdas read existing tables
(`ai_analyses`, `SENSOR_DATA`). The alerts log needs a brand-new table:

```sql
CREATE TABLE IF NOT EXISTS user_alerts (
  alert_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  homeid      VARCHAR(64) NOT NULL,
  userid      VARCHAR(64) NOT NULL,
  title       TEXT NOT NULL,
  description TEXT,
  alert_type  VARCHAR(32) NOT NULL,
  alert_level VARCHAR(16) NOT NULL,
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_alerts_owner
  ON user_alerts(homeid, userid, created_at DESC);
```

Run that once in psql (or your RDS Query Editor) before deploying
`saveAlertEvent`.

## Smoke checklist after deploy

- [ ] `GET /emotion-history` returns `{"entries": [...]}` with 200
- [ ] `GET /sensor-history?hours=12` returns `{"readings": [...]}` with 200
- [ ] `POST /alerts` returns `{"alert_id": "..."}` and the row appears in `user_alerts`
- [ ] `GET /alerts` returns recent rows for the calling user
- [ ] Open the app → Emotion Hub → heatmap fills with rows from RDS
- [ ] Dashboard sparkline shows immediately (no "collecting trend…")
- [ ] Restart the app → notifications still there
