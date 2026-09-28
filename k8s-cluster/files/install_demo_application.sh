#! /bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

######CONSTANTS######
BASE_DIRECTORY=/home/tuz/k8s
NAMESPACE_NAME=app
APPLICATION_NAME=syngx
#####################


sudo tee $BASE_DIRECTORY/manifests/application-namespace.yaml > /dev/null <<EOF
kind: Namespace
apiVersion: v1
metadata:
  name: $NAMESPACE_NAME
  labels:
    istio-injection: enabled
EOF

sudo tee $BASE_DIRECTORY/manifests/application-configmap.yaml > /dev/null <<EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: $APPLICATION_NAME-cm-custom
  namespace: $NAMESPACE_NAME
data:
  nginx.conf: |
    user nginx;
    worker_processes auto;
    pid /run/nginx.pid;
    error_log /var/log/nginx/error.log;
    include /etc/nginx/modules-enabled/*.conf;

    events {
        worker_connections 1024;
    }

    http {
        server {
            listen 8080;

            location /actuator/health {
                return 200 '/actuator/health';
            }

            location /actuator/health/liveness {
                return 200 '/actuator/health/liveness';
            }

            location /integration/api/user {
                return 200 '/integration/api/user';
            }
        }
    }
EOF

sudo tee $BASE_DIRECTORY/manifests/application-deployment.yaml > /dev/null <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  labels:
    app: $APPLICATION_NAME
  name: $APPLICATION_NAME
  namespace: $NAMESPACE_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/instance: $APPLICATION_NAME
      app.kubernetes.io/name: $APPLICATION_NAME
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 100%
      maxUnavailable: 50%
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: $APPLICATION_NAME
        app.kubernetes.io/name: $APPLICATION_NAME
      annotations:
        sidecar.istio.io/inject: "true"
        sidecar.istio.io/proxyCPU: "50m"
        sidecar.istio.io/proxyMemory: "100Mi"
        sidecar.istio.io/proxyCPULimit: "50m"
        sidecar.istio.io/proxyMemoryLimit: "100Mi"
    spec:
      serviceAccount: "default"
      volumes:
        - name: run-vol
          emptyDir: {}
        - name: var-vol
          emptyDir: {}
        - name: $APPLICATION_NAME-cm-custom-vol
          configMap:
            name: $APPLICATION_NAME-cm-custom
            defaultMode: 256
            items:
              - key: nginx.conf
                path: nginx.conf
      containers:
        - name: $APPLICATION_NAME
          imagePullPolicy: IfNotPresent
          image: docker.io/library/nginx:1.29.6
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
              scheme: HTTP
            timeoutSeconds: 5
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 4
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
              scheme: HTTP
            initialDelaySeconds: 0
            timeoutSeconds: 5
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 4
          startupProbe:
            httpGet:
              path: /actuator/health
              port: 8080
              scheme: HTTP
            failureThreshold: 60
            periodSeconds: 5
          resources:
            limits:
              cpu: 50m
              memory: 100Mi
            requests:
              cpu: 50m
              memory: 100Mi
          volumeMounts:
            - name: run-vol
              mountPath: /run
            - name: var-vol
              mountPath: /var/log/nginx
            - name: $APPLICATION_NAME-cm-custom-vol
              readOnly: true
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app.kubernetes.io/name
                      operator: In
                      values:
                        - $APPLICATION_NAME
                topologyKey: kubernetes.io/hostname
EOF

sudo tee $BASE_DIRECTORY/manifests/application-service.yaml > /dev/null <<EOF
kind: Service
apiVersion: v1
metadata:
  name: $APPLICATION_NAME
  namespace: $NAMESPACE_NAME
  labels:
    app.kubernetes.io/instance: $APPLICATION_NAME
    app.kubernetes.io/name: $APPLICATION_NAME
spec:
  ports:
    - name: tcp-8080
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app.kubernetes.io/instance: $APPLICATION_NAME
    app.kubernetes.io/name: $APPLICATION_NAME
EOF

sudo tee $BASE_DIRECTORY/manifests/application-ingress.yaml > /dev/null <<EOF
kind: Ingress
apiVersion: networking.k8s.io/v1
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/default-backend: ingressgateway-$NAMESPACE_NAME
    nginx.ingress.kubernetes.io/secure-backends: 'true'
    nginx.ingress.kubernetes.io/ssl-passthrough: 'true'
  name: $NAMESPACE_NAME-http-$APPLICATION_NAME
  namespace: $NAMESPACE_NAME
  labels:
    app: http-ingress
spec:
  rules:
    - host: $APPLICATION_NAME.$NAMESPACE_NAME.k8s.ru
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ingressgateway-$NAMESPACE_NAME
                port:
                  number: 8443
EOF

sudo tee $BASE_DIRECTORY/manifests/istio-ingressgateway.yaml > /dev/null <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: ingressgateway-$NAMESPACE_NAME
  namespace: $NAMESPACE_NAME
  labels:
    app: ingressgateway-$NAMESPACE_NAME
    app.kubernetes.io/instance: ingressgateway-$NAMESPACE_NAME
    app.kubernetes.io/name: ingressgateway-$NAMESPACE_NAME
    app.kubernetes.io/part-of: istio
    istio: ingressgateway-$NAMESPACE_NAME
    istio.io/dataplane-mode: none
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingressgateway-$NAMESPACE_NAME
      istio: ingressgateway-$NAMESPACE_NAME
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 100%
      maxUnavailable: 50%
  template:
    metadata:
      labels:
        app: ingressgateway-$NAMESPACE_NAME
        app.kubernetes.io/instance: ingressgateway-$NAMESPACE_NAME
        app.kubernetes.io/name: ingressgateway-$NAMESPACE_NAME
        app.kubernetes.io/part-of: istio
        istio: ingressgateway-$NAMESPACE_NAME
        istio.io/dataplane-mode: none
        istio.io/rev: default
        sidecar.istio.io/inject: 'true'
      annotations:
        inject.istio.io/templates: gateway
        prometheus.io/path: /stats/prometheus
        prometheus.io/port: '15020'
        prometheus.io/scrape: 'true'
        sidecar.istio.io/inject: 'true'
    spec:
# TODO !!!
      volumes:
        - name: app-tls
          projected:
            sources:
              - secret:
                  name: app-tls-server-cert
                  items:
                    - key: server.crt
                      path: server.crt
              - secret:
                  name: app-tls-server-key
                  items:
                    - key: server.key
                      path: server.key
# TODO !!!
      containers:
        - name: istio-proxy
          image: auto
          ports:
            - containerPort: 8443
              name: https
              protocol: TCP
          resources:
            limits:
              cpu: 500m
              memory: 200Mi
            requests:
              cpu: 100m
              memory: 100Mi
# TODO !!!
          volumeMounts:
            - name: app-tls
              mountPath: /vlt/istio/secrets-crt
              readOnly: true
# TODO !!!
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: Always
          securityContext:
            capabilities:
              drop:
                - ALL
            privileged: false
            runAsNonRoot: true
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      serviceAccountName: default
      serviceAccount: default
      securityContext:
        sysctls:
          - name: net.ipv4.ip_unprivileged_port_start
            value: '0'
      schedulerName: default-scheduler
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
EOF

sudo tee $BASE_DIRECTORY/manifests/istio-service.yaml > /dev/null <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ingressgateway-$NAMESPACE_NAME
  namespace: $NAMESPACE_NAME
  labels:
    app: ingressgateway-$NAMESPACE_NAME
    istio: ingressgateway-$NAMESPACE_NAME
spec:
  ports:
    - name: rest-8443
      port: 8443
      targetPort: 8443
      protocol: TCP
  selector:
    app: ingressgateway-$NAMESPACE_NAME
    istio: ingressgateway-$NAMESPACE_NAME
EOF

sudo tee $BASE_DIRECTORY/manifests/istio-gateway.yaml > /dev/null <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: svc-https-gw-$NAMESPACE_NAME
  namespace: $NAMESPACE_NAME
spec:
  selector:
    istio: ingressgateway-$NAMESPACE_NAME
  servers:
    - hosts:
        - $APPLICATION_NAME.$NAMESPACE_NAME.k8s.ru
      port:
        name: rest-8443
        number: 8443
        protocol: HTTPS
      tls:
        mode: SIMPLE
        serverCertificate: /vlt/istio/secrets-crt/server.crt
        privateKey: /vlt/istio/secrets-crt/server.key
EOF

sudo tee $BASE_DIRECTORY/manifests/istio-virtualservice.yaml > /dev/null <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: ingress-$APPLICATION_NAME-vs
  namespace: $NAMESPACE_NAME
spec:
  exportTo:
    - .
  gateways:
    - svc-https-gw-$NAMESPACE_NAME
  hosts:
    - $APPLICATION_NAME.$NAMESPACE_NAME.k8s.ru
  http:
    - headers:
        request:
          remove:
            - X-Forwarded-For
            - X-Forwarded-Client-Cert
            - x-envoy-peer-metadata
      match:
        - uri:
            prefix: /app/$APPLICATION_NAME/
      rewrite:
        uri: /
      route:
        - destination:
            host: $APPLICATION_NAME
            port:
              number: 8080
EOF

sudo tee $BASE_DIRECTORY/manifests/istio-destinationrule.yaml > /dev/null <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: svc-https-mtls-before-ingress-dr
  namespace: $NAMESPACE_NAME
spec:
  exportTo:
    - .
  host: ingressgateway-$NAMESPACE_NAME
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    portLevelSettings:
      - port:
          number: 8080
        tls:
          mode: SIMPLE
EOF