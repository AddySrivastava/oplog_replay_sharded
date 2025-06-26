#!/bin/bash

# === CONFIGURATION ===
SHARD_URIS=(
  "mongodb://10.32.53.126:28021/?directConnection=true"
  "mongodb://10.32.53.126:28022/?directConnection=true"
  "mongodb://10.32.53.126:28023/?directConnection=true"
)
CONFIGSVR_URI="mongodb://10.32.53.126:28025/?directConnection=true"

BACKUP_DIR="/home/ec2-user/oplog_test_sharded"
TIMESTAMP_FILE="${BACKUP_DIR}/last_ts.txt"
TIMESTAMP_DIR=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="${BACKUP_DIR}/oplog_backup_${TIMESTAMP_DIR}"

# === GET LAST TIMESTAMP (or default to now - 20mins) ===
if [[ -f "$TIMESTAMP_FILE" ]]; then
  echo "📄 Found previous timestamp file."
  LAST_TS=$(cat "$TIMESTAMP_FILE")
else
  echo "📄 No timestamp file found. Defaulting to 24 hours ago."
  NOW=$(date +%s)
  LAST_TS=$((NOW - 1200))
fi

# Calculate current timestamp
NOW_TS=$(date +%s)

# Construct BSON Timestamp query
OPLOG_QUERY="{ \"ts\": { \"\$gte\": { \"\$timestamp\": { \"t\": $LAST_TS, \"i\": 1 } }, \"\$lt\": { \"\$timestamp\": { \"t\": $NOW_TS, \"i\": 1 } } } }"

echo "⬅️ Last processed TS: $LAST_TS"
echo "➡️ Current TS: $NOW_TS"
echo "Query: $OPLOG_QUERY"

# Create output directory
mkdir -p "$OUT_DIR"

# === FUNCTION TO DUMP OPLOG ===
dump_oplog() {
  local NAME=$1
  local URI=$2
  local DEST="${OUT_DIR}/${NAME}"
  mkdir -p "$DEST"

  echo "🔄 Dumping oplog.rs for $NAME..."

  mongodump --uri="$URI" \
    --db=local \
    --collection=oplog.rs \
    --query="$OPLOG_QUERY" \
    --out="$DEST"

  if [[ $? -eq 0 ]]; then
    echo "✅ $NAME dump successful."
  else
    echo "❌ $NAME dump failed."
  fi
}

# === MAIN LOOP ===
for i in "${!SHARD_URIS[@]}"; do
  dump_oplog "shard$((i + 1))" "${SHARD_URIS[$i]}"
done

dump_oplog "configsvr" "$CONFIGSVR_URI"

# === SAVE NEW TIMESTAMP ===
echo "$NOW_TS" > "$TIMESTAMP_FILE"
echo "📌 Updated last processed timestamp: $NOW_TS"

echo "✅ All dumps complete. Output directory: $OUT_DIR"
