#!/bin/bash

# === CONFIGURATION ===
BACKUP_DIR="/home/ec2-user/oplog_test_sharded"  # Root directory of all backups

# Map of shard names to their MongoDB URIs
declare -A SHARD_URIS
SHARD_URIS[shard1]="mongodb://63.32.53.126:29122/?directConnection=true"
SHARD_URIS[shard2]="mongodb://63.32.53.126:29123/?directConnection=true"
SHARD_URIS[shard3]="mongodb://63.32.53.126:29124/?directConnection=true"
SHARD_URIS[configsvr]="mongodb://63.32.53.126:29121/?directConnection=true"

# Optional oplog limit in "<seconds>:<ordinal>" format
OPLOG_LIMIT_TIMESTAMP=""  # e.g. "1721978046:1" or leave blank

# === SAFETY VALIDATION FOR OPLOG LIMIT FORMAT ===
if [[ -n "$OPLOG_LIMIT_TIMESTAMP" ]]; then
  if ! [[ "$OPLOG_LIMIT_TIMESTAMP" =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "ERROR: Invalid --oplogLimit format. Expected format is <seconds>:<ordinal>, e.g. 1721978046:1"
    exit 1
  fi
  echo "WARNING: Using --oplogLimit=$OPLOG_LIMIT_TIMESTAMP"
  echo "WARNING: Incorrect use of oplogLimit may cause data inconsistency."
fi

# === VALIDATE BACKUP DIRECTORY ===
if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "ERROR: Backup directory does not exist: $BACKUP_DIR"
  exit 1
fi

# === FIND BACKUP FOLDERS SORTED ASC ===
BACKUP_FOLDERS=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'oplog_backup_*' | sort)

if [[ -z "$BACKUP_FOLDERS" ]]; then
  echo "ERROR: No oplog_backup_* folders found in $BACKUP_DIR"
  exit 1
fi

# === FUNCTION TO RESTORE A SINGLE BSON FILE ===
restore_oplog() {
  local FOLDER="$1"
  local SHARD="$2"
  local URI="${SHARD_URIS[$SHARD]}"
  local BSON_FILE="${FOLDER}/${SHARD}/local/oplog.rs.bson"

  if [[ -z "$URI" ]]; then
    echo "ERROR: No URI configured for shard $SHARD"
    return 1
  fi

  if [[ ! -f "$BSON_FILE" ]]; then
    echo "WARNING: Oplog file not found for $SHARD in $FOLDER. Skipping."
    return 0
  fi

  echo "Restoring oplog for $SHARD from: $BSON_FILE"
  echo "Target URI: $URI"

  CMD=(mongorestore --uri="$URI" --oplogFile="$BSON_FILE" --oplogReplay empty/)
  if [[ -n "$OPLOG_LIMIT_TIMESTAMP" ]]; then
    CMD+=(--oplogLimit="$OPLOG_LIMIT_TIMESTAMP")
  fi

  "${CMD[@]}"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: mongorestore failed for $BSON_FILE"
    exit 2
  fi

  echo "Restore completed for: $BSON_FILE"
}

# === MAIN LOOP ===
for FOLDER in $BACKUP_FOLDERS; do
  echo "Processing backup folder: $FOLDER"

  for SHARD in "${!SHARD_URIS[@]}"; do
    restore_oplog "$FOLDER" "$SHARD"
  done
done

echo "All oplog restores completed successfully."
