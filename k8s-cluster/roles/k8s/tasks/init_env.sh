#! /bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }



info "Добавление Helm репозитория cilium"
helm repo add cilium https://helm.cilium.io/

info "Добавление Helm репозитория headlamp"
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/

info "Добавление Helm репозитория ingress-nginx"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

info "Обновление метаданных Helm добавленных репозиториев"
helm repo update



info "Создание директории $(pwd)/helm для конфигурации чартов"
mkdir -p helm

info "Вычисление ip адреса control-plane ноды"
k8s_ip=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
info "Вычислен следующий ip адрес: $k8s_ip"

info "Генерация конфигурации для helm чарта cilium в файл $(pwd)/helm/cilium.yaml"
cat <<EOF > helm/cilium.yaml
k8sServiceHost: "$k8s_ip"
k8sServicePort: "6443"
routingMode: tunnel
ipam:
  mode: "cluster-pool"
  operator:
    clusterPoolIPv4PodCIDRList:
      - "10.0.0.0/16"
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

info "Установка Helm чарта cilium"
helm install cilium cilium/cilium \
  --version 1.18.8 \
  --namespace kube-system \
  --create-namespace \
  -f helm/cilium.yaml

info "Ожидание пока все поды cilium с меткой app.kubernetes.io/name=cilium не будут в состоянии ready..."
kubectl wait --for=condition=ready pod \
  --namespace kube-system \
  --selector=app.kubernetes.io/name=cilium \
  --timeout=300s

info "Создание директории $(pwd)/manifests для манифестов"
mkdir -p manifests

info "Генерирация манифеста CiliumClusterwideNetworkPolicy в файл $(pwd)/manifests/ccnp.yaml"
cat <<EOF > manifests/ccnp.yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: host-firewall
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
EOF

info "Применение манифеста $(pwd)/manifests/ccnp.yaml"
kubectl apply -f manifests/ccnp.yaml
info "Ожидание применения правил host-firewall..."



info "Генерация конфигурации для helm чарта ingress-nginx в файл $(pwd)/helm/ingress-nginx.yaml"
cat <<EOF > helm/ingress.yaml
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

info "Установка Helm чарта ingress-nginx"
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f helm/ingress.yaml

info "Ожидание пока все поды ingress-nginx с меткой app.kubernetes.io/name=ingress-nginx не будут в состоянии ready..."
kubectl wait --for=condition=ready pod \
  --namespace ingress-nginx \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=300s



info "Установка Helm чарта headlamp"
helm install headlamp headlamp/headlamp --namespace headlamp --create-namespace

info "Ожидание пока все поды headlamp в неймспейсе headlamp не будут в состоянии ready..."
kubectl wait --for=condition=ready pod \
  --namespace headlamp \
  --all \
  --timeout=300s

info "Создание директории $(pwd)/headlamp_certs для серверных сертификатов Headlamp"
mkdir -p headlamp_certs

info "Генерация серверных сертификатов для Headlamp"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout certs/tls.key \
    -out certs/tls.crt \
    -subj "/CN=headlamp.k8s.ru/O=Big Penis"

info "Создание секрета headlamp-tls с серверными сертификатами для Headlamp"
kubectl create secret tls headlamp-tls \
    --key certs/tls.key \
    --cert certs/tls.crt \
    --namespace=headlamp

info "Генерирация манифеста Ingress для Headlamp в файл $(pwd)/manifests/ingress-headlamp.yaml"
cat <<EOF > manifests/ingress-headlamp.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
    nginx.org/websocket-services: "headlamp"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - headlamp.k8s.ru
      secretName: headlamp-tls
  rules:
    - host: headlamp.k8s.ru
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: headlamp
                port:
                  number: 80
EOF

info "Применение манифеста Ingress для Headlamp"
kubectl apply -f manifests/ingress-headlamp.yaml

info "Удаляем кластерную привязку роли для headlamp-admin"
kubectl delete clusterrolebinding headlamp-admin --ignore-not-found

info "Удаляем сервисный аккаунт headlamp-admin если он есть"
kubectl delete sa headlamp-admin -n headlamp --ignore-not-found

info "Создаем сервисный аккаунт headlamp-admin"
kubectl create sa headlamp-admin -n headlamp

info "Создаем кластерную привязку cluster-admin к headlamp-admin"
kubectl create clusterrolebinding headlamp-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=headlamp:headlamp-admin

info "Генерируем и записываем в файл токен для входа в Headlamp"
echo "HEADLAMP_TOKEN: $(kubectl create token headlamp-admin -n headlamp --duration=8760h)" > $(pwd)/script_output.log



info "Установка nginx"
apt-get install -y nginx-extras

info "Применение конфигурации nginx"
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

  server {
    listen 8080;

    location / {
      return 200 '8080';
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

info "Проверка конфигурации nginx"
if nginx -t; then
    success "Конфигурация корректна"
else
    error "Ошибка в конфигурации"
    exit 1
fi

info "Выполняется перезапуск nginx"
sudo systemctl restart nginx



info "Скачивание istioctl..."
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.29.1 TARGET_ARCH=x86_64 sh -

info "Копирование бинарного файла istioctl в директорию /usr/local/bin/"
sudo cp istio-1.29.1/bin/istioctl /usr/local/bin/

info "Назначение прав на исполнение файлу /usr/local/bin/istioctl"
sudo chmod +x /usr/local/bin/istioctl

info "Установка Istio"
istioctl install \
  --set profile=minimal \
  --set values.gateways.istio-ingressgateway.enabled=false \
  --set values.global.proxy.autoInject=disabled \
  --set values.global.proxy.enableCoreDump=false \
  --set values.global.proxy.privileged=true \
  --set meshConfig.accessLogFile=/dev/stdout \
  -y

info "Ожидание пока все поды Istio в неймспейсе istio-system не будут в состоянии ready..."
kubectl wait --for=condition=ready pod \
  --namespace istio-system \
  --all \
  --timeout=300s



info "Генерация манифеста неймспейса прикладных приложений app"
cat <<EOF > manifests/namespace-app.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    istio.io/rev: default
EOF

info "Применение манифеста неймспейса прикладных приложений app"
kubectl apply -f manifests/namespace-app.yaml



info "Создание директории $(pwd)/ingressgateway_certs для ingressgateway сертификатов"
mkdir -p ingressgateway_certs

info "Генерация ingressgateway сертификатов"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ingressgateway_certs/tls.key \
    -out ingressgateway_certs/tls.crt \
    -subj "/CN=app.naebank.k8s.ru/O=Big Penis"

info "Создание секрета с серверными сертификатами ingressgateway"
kubectl create secret tls ingressgateway-tls \
    --key ingressgateway_certs/tls.key \
    --cert ingressgateway_certs/tls.crt \
    --namespace=app
