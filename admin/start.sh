#!/usr/bin/env bash
# 长安控车 · 独立网站后台 一键启动
# 用法：  ./start.sh
#         PORT=9000 ADMIN_PASSWORD=你的密码 ./start.sh
set -e
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "未检测到 Node.js，请先安装 Node 18+ 后重试。" >&2
  exit 1
fi

export PORT="${PORT:-8787}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin888}"

echo "后台地址： http://localhost:${PORT}"
echo "后台密码： ${ADMIN_PASSWORD}"
echo "App 侧请在「我的 → 网站后台」填写此服务地址。"
echo "----------------------------------------------"
exec node server.js
