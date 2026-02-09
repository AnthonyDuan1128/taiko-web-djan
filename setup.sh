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

echo "部署完成（直接监听 80 端口）"