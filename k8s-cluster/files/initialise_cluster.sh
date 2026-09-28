#! /bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

MASTER_IP=192.168.122.10
POD_NETWORK_CIDR=10.0.0.0/16
BASE_DIRECTORY=/home/tuz/k8s
TUZ_NAME=tuz

info "Инициализация master ноды"
#=====
kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=$POD_NETWORK_CIDR
#=====

info "Получение команды для подключения worker нод"
#=====
mkdir -p $BASE_DIRECTORY
kubeadm token create --print-join-command > $BASE_DIRECTORY/kubeadm-join-worker.sh
chmod 770 $BASE_DIRECTORY
chmod 660 $BASE_DIRECTORY/kubeadm-join-worker.sh
chown -R tuz:tuz $BASE_DIRECTORY
success "Команда для подключения worker нод:\n\n$(cat $BASE_DIRECTORY/kubeadm-join-worker.sh)\n\n"
read -sn1 -p "Выполните подключение worker нод, а затем нажмите любую клавишу для продолжения..."
printf '\n'
#=====

mkdir -p $BASE_DIRECTORY/.kube
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf $BASE_DIRECTORY/.kube/config
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $TUZ_NAME:$TUZ_NAME $BASE_DIRECTORY/.kube/config
chown root:root /root/.kube/config