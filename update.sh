#!/usr/bin/env bash
set -Eeuo pipefail

if [ "${EUID}" -ne 0 ]; then echo "需要 root 权限"; exit 1; fi

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
DEST_DIR=/srv/taiko-web
SONGS_DIR="$DEST_DIR/public/songs"
BACKUP_DIR="$DEST_DIR/.backup_songs_$(date +%Y%m%d_%H%M%S)"

systemctl stop taiko-web || true

if [ -d "$SONGS_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  rsync -a "$SONGS_DIR/" "$BACKUP_DIR/" || cp -a "$SONGS_DIR/." "$BACKUP_DIR/"
fi

mkdir -p "$DEST_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.venv' \
  --exclude 'public/songs' \
  "$SRC_DIR/" "$DEST_DIR/"

if [ -x "$DEST_DIR/.venv/bin/pip" ]; then
  "$DEST_DIR/.venv/bin/pip" install -U pip
  "$DEST_DIR/.venv/bin/pip" install -r "$DEST_DIR/requirements.txt"
fi

chown -R www-data:www-data "$DEST_DIR"

if [ -d "$BACKUP_DIR" ]; then
  mkdir -p "$SONGS_DIR"
  rsync -a "$BACKUP_DIR/" "$SONGS_DIR/" || cp -a "$BACKUP_DIR/." "$SONGS_DIR/"
fi

systemctl daemon-reload || true
systemctl restart taiko-web || systemctl start taiko-web || true

systemctl is-active --quiet taiko-web