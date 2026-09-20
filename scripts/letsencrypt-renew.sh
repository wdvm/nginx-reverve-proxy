#!/bin/sh
set -e

# Renova certificados Let's Encrypt e recarrega o Nginx.
# Agende no cron da EC2, duas vezes por dia:
#   15 3,15 * * * /home/ubuntu/nginx-proxy/scripts/letsencrypt-renew.sh >>/var/log/letsencrypt-renew.log 2>&1

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

docker compose --profile certs run --rm certbot renew --webroot -w /var/www/certbot --quiet
docker compose exec nginx nginx -s reload
