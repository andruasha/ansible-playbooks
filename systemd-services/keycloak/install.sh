#! /bin/bash

sudo apt update

sudo apt install openjdk-25-jdk

wget https://github.com/keycloak/keycloak/releases/download/26.6.3/keycloak-26.6.3.zip

unzip keycloak-26.6.3.zip

sudo groupadd -r keycloak

sudo useradd -r -g keycloak -s /sbin/nologin keycloak

sudo mkdir -p /opt/keycloak

sudo mv keycloak-26.6.3/* /opt/keycloak/

sudo chown -R keycloak:keycloak /opt/keycloak

sudo tee /usr/lib/systemd/system/keycloak.service > /dev/null <<'EOF'
[Unit]
Description="Keycloak"
After=network.target postgresql.service

[Service]
User=keycloak
Group=keycloak
ExecStart=/opt/keycloak/bin/kc.sh start
SuccessExitStatus=143
TimeoutStopSec=10
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

sudo apt install postgresql

sudo -u postgres psql -c "CREATE USER tuz_keycloak WITH SUPERUSER PASSWORD 'password';"
sudo -u postgres psql -c "CREATE DATABASE keycloak OWNER tuz_keycloak;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE keycloak TO tuz_keycloak;"

sudo tee /opt/keycloak/conf/keycloak.conf > /dev/null <<'EOF'
db=postgres
db-username=tuz_keycloak
db-password=password
db-url=jdbc:postgresql://127.0.0.1:5432/keycloak
http-enabled=true
hostname=keycloak.penis.ru
EOF