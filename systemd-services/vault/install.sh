wget https://releases.hashicorp.com/vault/2.0.2/vault_2.0.2_linux_amd64.zip

unzip vault_2.0.2_linux_amd64.zip

sudo mv vault /usr/local/bin/

sudo mkdir -p /etc/vault.d

sudo mkdir -p /opt/vault/data

sudo tee /etc/vault.d/vault.hcl > /dev/null <<'EOF'
ui = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1
}
EOF

sudo groupadd -r vault

sudo useradd -r -g vault -s /sbin/nologin vault

sudo chown vault:vault /usr/local/bin/vault

sudo chown -R vault:vault /etc/vault

sudo chown -R vault:vault /opt/vault/data

sudo tee /usr/lib/systemd/system/keycloak.service > /dev/null <<'EOF'
[Unit]
Description="HashiCorp Vault"
After=network.target

[Service]
User=vault
Group=vault
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP
KillMode=process
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF