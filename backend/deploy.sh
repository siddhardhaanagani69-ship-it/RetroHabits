#!/bin/zsh
# Push backend code (and .env, minus the Vultr key) to the Vultr server and restart.
#   ./deploy.sh            code only
#   ./deploy.sh --env      code + .env (+ gmail_token.json if present)
set -e
cd "$(dirname "$0")"
HOST=root@45.76.234.93
KEY=~/.ssh/retrohabits_vultr
run() { ssh -i $KEY -o BatchMode=yes $HOST "$@"; }

COPYFILE_DISABLE=1 tar --no-xattrs -czf /tmp/retrohabits-backend.tgz main.py ripple.py requirements.txt schema.sql init_db.py
scp -q -i $KEY /tmp/retrohabits-backend.tgz $HOST:/tmp/backend.tgz
if [[ "$1" == "--env" ]]; then
  grep -v '^VULTR_API_KEY=' .env | run 'install -m 600 -o app -g app /dev/stdin /opt/retrohabits/.env'
  if [[ -f gmail_token.json ]]; then
    run 'install -m 600 -o app -g app /dev/stdin /opt/retrohabits/gmail_token.json' < gmail_token.json
  fi
fi
run 'cd /opt/retrohabits && tar xzf /tmp/backend.tgz && rm /tmp/backend.tgz && chown -R app:app . &&
     sudo -u app .venv/bin/pip install -q -r requirements.txt && systemctl restart retrohabits && sleep 2 &&
     systemctl is-active retrohabits'
curl -s https://45-76-234-93.sslip.io/health; echo
