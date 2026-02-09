# 太鼓 Web（移除 tjaf 依赖版）

仓库地址（主分支）：

https://git.20091128.xyz/AnthonyDuan/taiko-web-without-tjaf/src/branch/main/

## 功能概述

- 移除了对 `tjaf` 外部库的依赖，改用项目内置 TJA 解析实现（`tjaf.py`）
- 保持原有上传、歌曲管理、预览生成等功能

## 快速部署（推荐）

适用系统：Ubuntu 20.04+/22.04+/24.04（需 root）

```bash
bash setup.sh
```

部署完成后访问：

```
http://<服务器IP>/
```

### 脚本做了什么

- 安装依赖：`python3`、`python3-venv`、`python3-pip`、`git`、`ffmpeg`、`rsync`、`curl`、`gnupg`、`libcap2-bin`
- 安装并启动：`MongoDB` 与 `Redis`
- 同步项目到 `/srv/taiko-web`，创建虚拟环境并安装 `requirements.txt`
- 如无 `config.py`，从 `config.example.py` 复制默认配置
- 为虚拟环境 `python3` 赋予低位端口绑定权限（`setcap cap_net_bind_service=+ep`）
- 创建 `systemd` 服务，使用 `gunicorn` 直接监听 `0.0.0.0:80`
- 开放防火墙 `80/tcp`（如系统启用了 `ufw`）

## 全命令部署（使用 Docker 部署 MongoDB）

适用系统：Ubuntu 20.04+/22.04+/24.04（需 root），MongoDB 通过 Docker 启动，其余步骤照常。

1. 安装 Docker 并启动：
   ```bash
   sudo apt update
   sudo apt install -y docker.io
   sudo systemctl enable --now docker
   ```
2. 启动 MongoDB 容器（持久化到 `/srv/taiko-web-mongo`，监听 `27017`）：
   ```bash
   sudo mkdir -p /srv/taiko-web-mongo
   sudo docker run -d \
     --name taiko-web-mongo \
     --restart unless-stopped \
     -v /srv/taiko-web-mongo:/data/db \
     -p 27017:27017 \
     mongo:6
   ```
   如需开启认证，可加上：
   ```bash
   -e MONGO_INITDB_ROOT_USERNAME=<用户名> -e MONGO_INITDB_ROOT_PASSWORD=<强密码>
   ```
   并在应用侧通过环境变量指定 Host：
   ```bash
   export TAIKO_WEB_MONGO_HOST=127.0.0.1:27017
   ```
3. 安装并启动 Redis（照常）：
   ```bash
   sudo apt install -y redis-server
   sudo systemctl enable --now redis-server
   ```
4. 准备项目与虚拟环境（照常）：
   ```bash
   sudo mkdir -p /srv/taiko-web
   sudo rsync -a --delete --exclude '.git' --exclude '.venv' . /srv/taiko-web/
   sudo python3 -m venv /srv/taiko-web/.venv
   sudo /srv/taiko-web/.venv/bin/pip install -U pip
   sudo /srv/taiko-web/.venv/bin/pip install -r /srv/taiko-web/requirements.txt
   sudo cp /srv/taiko-web/config.example.py /srv/taiko-web/config.py
   ```
5. 赋予 80 端口绑定权限并启动：
   ```bash
   sudo setcap 'cap_net_bind_service=+ep' /srv/taiko-web/.venv/bin/python3
   export TAIKO_WEB_MONGO_HOST=${TAIKO_WEB_MONGO_HOST:-127.0.0.1:27017}
   sudo /srv/taiko-web/.venv/bin/gunicorn -b 0.0.0.0:80 app:app
   ```

## 手动部署（可选）

1. 安装依赖：
   ```bash
   sudo apt update
   sudo apt install -y python3 python3-venv python3-pip git ffmpeg rsync libcap2-bin
   ```
2. 安装并启动数据库：
   ```bash
   sudo apt install -y mongodb redis-server
   sudo systemctl enable --now mongod redis-server
   ```
3. 准备项目与虚拟环境：
   ```bash
   sudo mkdir -p /srv/taiko-web
   sudo rsync -a --delete --exclude '.git' --exclude '.venv' . /srv/taiko-web/
   sudo python3 -m venv /srv/taiko-web/.venv
   sudo /srv/taiko-web/.venv/bin/pip install -U pip
   sudo /srv/taiko-web/.venv/bin/pip install -r /srv/taiko-web/requirements.txt
   ```
4. 配置文件：
   ```bash
   sudo cp /srv/taiko-web/config.example.py /srv/taiko-web/config.py
   ```
5. 赋予 80 端口绑定权限并启动：
   ```bash
   sudo setcap 'cap_net_bind_service=+ep' /srv/taiko-web/.venv/bin/python3
   sudo /srv/taiko-web/.venv/bin/gunicorn -b 0.0.0.0:80 app:app
   ```

## 开发与调试

```bash
pip install -r requirements.txt
```

本地快速启动（需要本机 MongoDB 与 Redis 已就绪）：

```bash
flask run
```

也可使用容器快速拉起本地数据库：

```bash
docker run --detach \
  --name taiko-web-mongo-debug \
  --volume taiko-web-mongo-debug:/data/db \
  --publish 27017:27017 \
  mongo

docker run --detach \
  --name taiko-web-redis-debug \
  --volume taiko-web-redis-debug:/data \
  --publish 6379:6379 \
  redis
```

---

如需将监听接口改为仅内网或增加并发工作数（例如 `--workers 4`），可在 `setup.sh` 或 `systemd` 服务中调整。
## 歌曲类型（Type）

- 可选枚举：
  - 01 Pop
  - 02 Anime
  - 03 Vocaloid
  - 04 Children and Folk
  - 05 Variety
  - 06 Classical
  - 07 Game Music
  - 08 Live Festival Mode
  - 09 Namco Original
  - 10 Taiko Towers
  - 11 Dan Dojo

### 上传要求
- 上传表单新增必填字段 `song_type`，取值为上述枚举之一
- 成功后将写入 MongoDB `songs.song_type`

### API 扩展
- `GET /api/songs?type=<歌曲类型>` 按类型过滤返回启用歌曲
- 示例：`/api/songs?type=02%20Anime`
- 返回项包含 `song_type` 字段

### 前端切换
- 在歌曲选择页顶部显示当前歌曲类型标签
- 使用左右跳转（Shift+左右或肩键）自动切换类型并刷新列表
