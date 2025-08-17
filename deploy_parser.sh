#!/usr/bin/env bash
# файл: deploy_parser.sh

set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(dirname "$(readlink -f "$0")")"
cd "$PROJECT_ROOT"

echo "🛈  Pulling latest changes from GitHub (main repo)..."
git pull --ff-only

echo "🛈  Forcing rebuild to pull latest parser_GETenders updates..."
# --no-cache важен, чтобы git clone в Dockerfile точно сработал
docker compose build --no-cache backend frontend

echo "🛈  Restarting containers..."
docker compose up -d

echo "🛈  Cleaning up dangling images..."
docker image prune -f --filter "dangling=true"

echo "✅  Deployment complete. Check the admin panel 🎉"
