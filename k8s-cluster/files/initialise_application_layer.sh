#! /bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

######CONSTANTS######
MASTER_IP=192.168.122.10
POD_NETWORK_CIDR=10.0.0.0/16
BASE_DIRECTORY=/home/tuz/k8s
CILIUM_VERSION=1.18.8
INGRESS_NGINX_VERSION=1.15.1
ISTIO_VERSION=1.31.1
#####################


info "Добавление Helm репозиториев cilium, ingress-nginx, istio"
#=====
helm repo add cilium https://helm.cilium.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add istio https://blob.istio.io/istio-release/charts
helm repo update
#=====

info "Создание директорий для конфигураций"
#=====
mkdir -p $BASE_DIRECTORY/helm
mkdir -p $BASE_DIRECTORY/manifests
#=====

info "Генерация конфигурации для helm чарта cilium"
#=====
cat <<EOF > $BASE_DIRECTORY/helm/cilium.yaml
k8sServiceHost: "$MASTER_IP"
k8sServicePort: "6443"
routingMode: tunnel
ipam:
  mode: "cluster-pool"
  operator:
    clusterPoolIPv4PodCIDRList:
      - "$POD_NETWORK_CIDR"
cluster:
  name: "my-cluster"
hubble:
  enabled: false
kubeProxyReplacement: "true"
enableL7Proxy: false
nodePort:
  enabled: true
externalIPs:
  enabled: true
mtu: 1450
bpf:
  masquerade: true
enableHostReachableServices: true
hostFirewall:
    enabled: true
policyEnforcementMode: "default"
EOF
#=====

info "Установка Helm чарта cilium"
#=====
helm install cilium cilium/cilium \
  --version $CILIUM_VERSION \
  --namespace kube-system \
  --create-namespace \
  -f $BASE_DIRECTORY/helm/cilium.yaml
#=====

info "Ожидание пока все поды в неймспейсе kube-system не будут в состоянии ready..."
#=====
kubectl wait --for=condition=ready pod \
  --namespace kube-system \
  --all \
  --timeout=300s
#=====

info "Генерирация манифеста CiliumClusterwideNetworkPolicy"
#=====
cat <<EOF > $BASE_DIRECTORY/manifests/ccnp.yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: host-firewall
  namespace: kube-system
spec:
  nodeSelector: {}
  ingress:
    - fromEntities:
        - cluster

    - fromEntities:
        - world
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
            - port: "8308"
              protocol: TCP
            - port: "8443"
              protocol: TCP
            - port: "8200"
              protocol: TCP
EOF
#=====

info "Применение манифеста $BASE_DIRECTORY/manifests/ccnp.yaml"
#=====
kubectl apply -f $BASE_DIRECTORY/manifests/ccnp.yaml
info "Ожидание применения правил host-firewall..."
sleep 10
#=====

info "Генерация конфигурации для helm чарта ingress-nginx"
#=====
cat <<EOF > $BASE_DIRECTORY/helm/ingress.yaml
controller:
  kind: DaemonSet
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
  hostNetwork: false
  dnsPolicy: ClusterFirst
  admissionWebhooks:
    enabled: true
  metrics:
    enabled: true
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
  updateStrategy:
    type: RollingUpdate
  tolerations:
    - operator: Exists
  nodeSelector:
    kubernetes.io/os: linux
EOF
#=====

info "Установка Helm чарта ingress-nginx"
#=====
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --version $INGRESS_NGINX_VERSION \
  --namespace ingress-nginx \
  --create-namespace \
  -f $BASE_DIRECTORY/helm/ingress.yaml
#=====

info "Ожидание пока все поды в неймспейсе ingress-nginx не будут в состоянии ready..."
#=====
kubectl wait --for=condition=ready pod \
  --namespace ingress-nginx \
  --all \
  --timeout=300s
#=====

info "Установка nginx"
#=====
sudo apt install -y nginx-extras
#=====

info "Применение конфигурации nginx"
#=====
sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
  worker_connections 768;
}

http {
  server {
    listen 80;

    location / {
      proxy_pass http://127.0.0.1:30080;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
  }
}

stream {
    server {
        listen 443;
        proxy_pass 127.0.0.1:30443;
    }
}
EOF
#=====

info "Проверка конфигурации nginx"
#=====
if nginx -t; then
    success "Конфигурация корректна"
else
    error "Ошибка в конфигурации"
    exit 1
fi
#=====

info "Перезапуск nginx"
#=====
sudo systemctl restart nginx
#=====

info "Установка helm чарта istio-base (istio CRDs)"
#=====
helm install istio-base istio/base \
  --version $ISTIO_VERSION \
  --namespace istio-system \
  --create-namespace \
  --set defaultRevision=default
#=====

info "Установка helm чарта istio-base (istio control plane)"
#=====
helm install istiod istio/istiod \
  --version $ISTIO_VERSION \
  --namespace istio-system \
  --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY \
  --wait
#=====