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

sudo chown -R vault:vault /etc/vault.d

sudo chown -R vault:vault /opt/vault/data

sudo tee /usr/lib/systemd/system/vault.service > /dev/null <<'EOF'
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

##### VAULT PKI CONFIGURATION #####
# source: https://itdraft.ru/2020/12/02/hashicorp-vault-kak-czentr-sertifikaczii-ca-vault-pki/
export VAULT_ADDR='http://127.0.0.1:8200'

vault secrets enable \
    -path=root_ca \
    -description="PKI Root CA" \
    -max-lease-ttl="262800h" \
    pki

vault write -format=json root_ca/root/generate/internal \
    common_name="Root Certificate Authority" \
    country="RU" \
    locality="Moscow" \
    organization="Big Penis LLC" \
    ou="IT" \
    ttl="262800h" > pki-root-ca.json

cat pki-root-ca.json | jq -r .data.certificate > rootCA.pem

vault write root_ca/config/urls \
    issuing_certificates="http://vault.k8s.ru:8200/v1/root_ca/ca" \
    crl_distribution_points="http://vault.k8s.ru:8200/v1/root_ca/crl"

vault secrets enable \
    -path=int_ca \
    -description="PKI Intermediate CA" \
    -max-lease-ttl="175200h" \
    pki

vault write -format=json int_ca/intermediate/generate/internal \
   common_name="Intermediate CA" \
   country="RU" \
   locality="Moscow" \
   organization="Big Penis LLC" \
   ou="IT" \
   ttl="175200h" | jq -r '.data.csr' > pki_intermediate_ca.csr

vault write -format=json root_ca/root/sign-intermediate csr=@pki_intermediate_ca.csr \
   country="RU" \
   locality="Moscow" \
   organization="Big Penis LLC" \
   ou="IT" \
   format=pem_bundle \
   ttl="175200h" | jq -r '.data.certificate' > intermediateCA.cert.pem

vault write int_ca/intermediate/set-signed \
    certificate=@intermediateCA.cert.pem

vault write int_ca/config/urls \
    issuing_certificates="http://vault.k8s.ru:8200/v1/int_ca/ca" \
    crl_distribution_points="http://vault.k8s.ru:8200/v1/int_ca/crl"

vault write int_ca/roles/server \
    country="RU" \
    locality="Moscow" \
    organization="Big Penis LLC" \
    ou="IT" \
    allowed_domains="*.k8s.ru" \
    allow_subdomains=true \
    max_ttl="87600h" \
    key_bits="2048" \
    key_type="rsa" \
    allow_any_name=false \
    allow_bare_domains=false \
    allow_glob_domain=true \
    allow_ip_sans=true \
    allow_localhost=false \
    client_flag=false \
    server_flag=true \
    enforce_hostnames=true \
    key_usage="DigitalSignature,KeyEncipherment" \
    ext_key_usage="ServerAuth" \
    require_cn=true

vault write int_ca/roles/client \
    country="RU" \
    locality="Moscow" \
    organization="Big Penis LLC" \
    ou="IT" \
    allow_subdomains=true \
    max_ttl="87600h" \
    key_bits="2048" \
    key_type="rsa" \
    allow_any_name=true \
    allow_bare_domains=false \
    allow_glob_domain=true \
    allow_ip_sans=false \
    allow_localhost=false \
    client_flag=true \
    server_flag=false \
    enforce_hostnames=false \
    key_usage="DigitalSignature" \
    ext_key_usage="ClientAuth" \
    require_cn=true

##### НАСТРОЙКА АУТЕНТИФИКАЦИИ В VAULT ЧЕРЕЗ KEYCLOAK #####
# source: https://skycloak.io/blog/keycloak-hashicorp-vault-oidc-sso/
# Не забыть настроить Group Membership mapper чтобы в JWT Появились groups