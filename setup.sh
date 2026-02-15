#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then echo "需要 root 权限"; exit 1; fi

. /etc/os-release || true
CODENAME=${VERSION_CODENAME:-}
VERSION=${VERSION_ID:-}

echo "更新系统软件源..."
apt-get update -y
echo "安装基础依赖..."
apt-get install -y python3 python3-venv python3-pip git ffmpeg rsync curl gnupg libcap2-bin

echo "安装并启动 MongoDB..."
MONGO_READY=false
if ! command -v mongod >/dev/null 2>&1; then
  if [ -n "$CODENAME" ] && echo "$CODENAME" | grep -Eq '^(focal|jammy)$'; then
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg || true
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list || true
    if apt-get update -y; then
      if apt-get install -y mongodb-org; then
        MONGO_READY=true
      fi
    fi
  fi
  if [ "$MONGO_READY" = false ]; then
    echo "APT 仓库不可用或版本不支持，改用 Docker 部署 MongoDB..."
    rm -f /etc/apt/sources.list.d/mongodb-org-7.0.list || true
    apt-get install -y docker.io
    systemctl enable --now docker || true
    mkdir -p /var/lib/mongo
    if ! docker ps -a --format '{{.Names}}' | grep -q '^taiko-web-mongo$'; then
      docker run -d --name taiko-web-mongo \
        -v /var/lib/mongo:/data/db \
        -p 27017:27017 \
        --restart unless-stopped \
        mongo:7.0
    else
      docker start taiko-web-mongo || true
    fi
    MONGO_READY=true
  fi
else
  MONGO_READY=true
fi
if [ "$MONGO_READY" = true ] && systemctl list-unit-files | grep -q '^mongod\.service'; then
  systemctl enable mongod || true
  systemctl restart mongod || systemctl start mongod || true
fi

echo "安装并启动 Redis..."
apt-get install -y redis-server
systemctl enable redis-server || true
systemctl restart redis-server || systemctl start redis-server || true

echo "同步项目到 /srv/taiko-web..."
mkdir -p /srv/taiko-web
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
rsync -a --delete --exclude '.git' --exclude '.venv' "$SRC_DIR/" /srv/taiko-web/

echo "预创建歌曲存储目录..."
mkdir -p /srv/taiko-web/public/songs

echo "创建并安装 Python 虚拟环境..."
python3 -m venv /srv/taiko-web/.venv
/srv/taiko-web/.venv/bin/pip install -U pip
/srv/taiko-web/.venv/bin/pip install -r /srv/taiko-web/requirements.txt

if [ ! -f /srv/taiko-web/config.py ] && [ -f /srv/taiko-web/config.example.py ]; then
  cp /srv/taiko-web/config.example.py /srv/taiko-web/config.py
fi

chown -R www-data:www-data /srv/taiko-web

echo "创建 systemd 服务..."
cat >/etc/systemd/system/taiko-web.service <<'EOF'
[Unit]
Description=Taiko Web
After=network.target mongod.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/srv/taiko-web
Environment=PYTHONUNBUFFERED=1
Environment=TAIKO_WEB_SONGS_DIR=/srv/taiko-web/public/songs
ExecStart=/srv/taiko-web/.venv/bin/gunicorn -b 0.0.0.0:80 app:app
Restart=always
User=www-data
Group=www-data
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable taiko-web
systemctl restart taiko-web

if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp || true
fi

echo "等待服务启动..."
API_URL="http://127.0.0.1:80"
for i in $(seq 1 30); do
  if curl -sf "${API_URL}/api/songs" >/dev/null 2>&1; then
    echo "服务已就绪"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "服务启动超时，跳过上传"
    echo "部署完成（直接监听 80 端口）"
    exit 0
  fi
  sleep 2
done

echo "上传段位道场样本数据..."
DAN_SAMPLE_DIR="$SRC_DIR/段位道场样本文件"
if [ -d "$DAN_SAMPLE_DIR" ]; then
  DAN_OK=0
  DAN_FAIL=0
  DAN_TOTAL=0

  upload_dan() {
    local dan_dir="$1"
    local tja_file
    tja_file=$(find "$dan_dir" -maxdepth 1 -name "*.tja" -type f | head -1)
    if [ -z "$tja_file" ]; then
      return 1
    fi

    # Build curl arguments: TJA file + all OGG audio files + song_type
    local curl_args=(-s -X POST "${API_URL}/api/upload")
    curl_args+=(-F "file_tja=@${tja_file}")
    curl_args+=(-F "song_type=11 Dan Dojo")

    local ogg_count=0
    while IFS= read -r -d '' ogg_file; do
      curl_args+=(-F "file_music[]=@${ogg_file}")
      ogg_count=$((ogg_count + 1))
    done < <(find "$dan_dir" -maxdepth 1 -name "*.ogg" -type f -print0)

    if [ "$ogg_count" -eq 0 ]; then
      echo "  ✗ $(basename "$dan_dir"): 缺少 OGG 音频文件"
      return 1
    fi

    local response
    response=$(curl "${curl_args[@]}" 2>/dev/null || echo '{"error":"请求失败"}')
    local name
    name=$(basename "$dan_dir")

    if echo "$response" | grep -q '"success".*:.*true'; then
      echo "  ✓ ${name} (${ogg_count} 个音频)"
      return 0
    else
      local err
      err=$(echo "$response" | grep -oP '"error"\s*:\s*"\K[^"]+' || echo "$response")
      echo "  ✗ ${name}: ${err}"
      return 1
    fi
  }

  # Iterate all Dan song directories (depth 2: version/dan_name/)
  while IFS= read -r -d '' dan_dir; do
    DAN_TOTAL=$((DAN_TOTAL + 1))
    if upload_dan "$dan_dir"; then
      DAN_OK=$((DAN_OK + 1))
    else
      DAN_FAIL=$((DAN_FAIL + 1))
    fi
  done < <(find "$DAN_SAMPLE_DIR" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)

  echo "段位道场上传完成: ${DAN_OK}/${DAN_TOTAL} 成功"
  if [ "$DAN_FAIL" -gt 0 ]; then
    echo "  ⚠ ${DAN_FAIL} 个失败"
  fi
else
  echo "未找到段位道场样本文件夹，跳过上传"
fi

echo "部署完成（直接监听 80 端口）"
