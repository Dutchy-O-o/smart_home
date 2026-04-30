-- DB cleanup for smart-home project
-- Run as a single transaction so partial failures roll back cleanly.
-- Verified target IDs from the user's database snapshot on 2026-04-29.

BEGIN;

-- ============================================================
-- 1. Drop duplicate "Living Room AC" and "Kitchen Stove"
--    (the existing Air Conditioner / Stove rows are kept,
--     they're already wired to Raspi via MQTT topics)
-- ============================================================
DELETE FROM actuator_current_states
WHERE propertyid IN (
    SELECT propertyid FROM actuator_properties
    WHERE deviceid IN (
        '69ddf0d3-563a-49fd-ade2-35f929f0bd05',  -- Living Room AC (duplicate)
        'dcab0373-e1b2-4714-8718-49a8d2e9055a'   -- Kitchen Stove (duplicate)
    )
);

DELETE FROM actuator_properties
WHERE deviceid IN (
    '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
    'dcab0373-e1b2-4714-8718-49a8d2e9055a'
);

DELETE FROM devices
WHERE deviceid IN (
    '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
    'dcab0373-e1b2-4714-8718-49a8d2e9055a'
);

-- ============================================================
-- 2. Rename existing "Stove" -> "Oven"
--    (the physical device label is staying the same; this is
--     just the user-facing name)
-- ============================================================
UPDATE devices
SET device_name = 'Oven'
WHERE deviceid = '238a35b9-f593-4c30-89a2-f43d0141a4f9';

-- ============================================================
-- 3. Remove "Blinds" entirely (UI no longer renders them).
--    Both homes have Blinds rows, so delete in both.
-- ============================================================
DELETE FROM actuator_current_states
WHERE propertyid IN (
    SELECT propertyid FROM actuator_properties
    WHERE deviceid IN (
        '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',  -- Blinds @ 757bfcc9 home
        'c608414b-3c92-4c9c-aef9-4921ec3b8234'   -- Blinds @ 2005a6aa home
    )
);

DELETE FROM actuator_properties
WHERE deviceid IN (
    '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
    'c608414b-3c92-4c9c-aef9-4921ec3b8234'
);

DELETE FROM devices
WHERE deviceid IN (
    '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
    'c608414b-3c92-4c9c-aef9-4921ec3b8234'
);

-- ============================================================
-- 4. Sanity check (read-only): the rows below should be gone,
--    and 'Oven' should appear once.
-- ============================================================
-- SELECT deviceid, device_name, device_type FROM devices
-- WHERE deviceid IN (
--     '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
--     'dcab0373-e1b2-4714-8718-49a8d2e9055a',
--     '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
--     'c608414b-3c92-4c9c-aef9-4921ec3b8234',
--     '238a35b9-f593-4c30-89a2-f43d0141a4f9'
-- );

COMMIT;
