sudo apt update
sudo apt install nginx-full


sudo groupadd nginx-deploy
sudo useradd -r -g nginx-deploy -m -s /bin/bash nginx-deploy


sudo tee /usr/local/bin/nginx-backup-create > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR=/var/backups/nginx
TS=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

ARCHIVE="$BACKUP_DIR/nginx-config-$TS.tar.gz"

tar -czf "$ARCHIVE" \
  /etc/nginx/nginx.conf \
  /etc/nginx/conf.d

echo "$ARCHIVE"
EOF

sudo chown root:root /usr/local/bin/nginx-backup-create
sudo chmod 700 /usr/local/bin/nginx-backup-create
sudo chmod +x /usr/local/bin/nginx-backup-create


sudo tee /usr/local/bin/nginx-backup-restore > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

ARCHIVE="$1"

test -f "$ARCHIVE"

TMP=$(mktemp -d)

tar -xzf "$ARCHIVE" -C "$TMP"

test -f "$TMP/etc/nginx/nginx.conf"
test -d "$TMP/etc/nginx/conf.d"

cp -f "$TMP/etc/nginx/nginx.conf" /etc/nginx/nginx.conf
rm -rf /etc/nginx/conf.d
cp -a "$TMP/etc/nginx/conf.d" /etc/nginx/

rm -rf "$TMP"
EOF

sudo chown root:root /usr/local/bin/nginx-backup-restore
sudo chmod 700 /usr/local/bin/nginx-backup-restore
sudo chmod +x /usr/local/bin/nginx-backup-restore


sudo tee /usr/local/bin/nginx-configuration-rsync > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

rm -rf /etc/nginx/conf.d
rsync -a --no-owner --no-group /home/nginx-deploy/nginx-staging/ /etc/nginx/
EOF

sudo chown root:root /usr/local/bin/nginx-configuration-rsync
sudo chmod 700 /usr/local/bin/nginx-configuration-rsync
sudo chmod +x /usr/local/bin/nginx-configuration-rsync


sudo tee /etc/sudoers.d/nginx-deploy > /dev/null <<'EOF'
nginx-deploy ALL=(root) NOPASSWD: \
    /usr/local/bin/nginx-backup-create, \
    /usr/local/bin/nginx-backup-restore *, \
    /usr/local/bin/nginx-configuration-rsync, \
    /bin/systemctl start nginx.service, \
    /bin/systemctl stop nginx.service, \
    /bin/systemctl restart nginx.service, \
    /bin/systemctl reload nginx.service, \
    /bin/systemctl status nginx.service, \
    /usr/sbin/nginx -t -c /home/nginx-deploy/nginx-staging/nginx.conf, \
    /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
EOF

sudo chmod 660 /etc/sudoers.d/nginx-deploy