#!/bin/sh
set -e

# Emite (ou renova) o certificado Let's Encrypt de nachapa.2ulabs.com.br
# e aponta o Nginx para fullchain/privkey.
#
# Uso, na pasta do nginx-proxy na EC2:
#   ACME_EMAIL=voce@email.com ./scripts/letsencrypt-nachapa.sh

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOMAIN="${ACME_DOMAIN:-nachapa.2ulabs.com.br}"
EMAIL="${ACME_EMAIL:?Defina ACME_EMAIL (ex.: ACME_EMAIL=voce@dominio.com ./scripts/letsencrypt-nachapa.sh)}"

mkdir -p certbot/www certbot/conf

docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload

docker compose --profile certs run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  --keep-until-expiring

CONF="nginx/conf.d/nachapa.conf"
if grep -q "/etc/nginx/ssl/nachapa.crt" "$CONF"; then
  python3 - "$CONF" "$DOMAIN" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
domain = sys.argv[2]
text = path.read_text()
text = text.replace(
    "ssl_certificate     /etc/nginx/ssl/nachapa.crt;",
    f"ssl_certificate     /etc/letsencrypt/live/{domain}/fullchain.pem;",
)
text = text.replace(
    "ssl_certificate_key /etc/nginx/ssl/nachapa.key;",
    f"ssl_certificate_key /etc/letsencrypt/live/{domain}/privkey.pem;",
)
path.write_text(text)
PY
fi

docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
echo "OK: HTTPS de https://${DOMAIN} deve usar Let's Encrypt."
