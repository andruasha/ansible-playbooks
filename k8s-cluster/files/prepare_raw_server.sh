#! /bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

######CONSTANTS######
CURRENT_USER_NAME=andrey
TECHNICAL_USER_NAME=tuz
SSH_PORT=22
KUBERNETES_VERSION=v1.37
#####################


info "Создание технической учетной записи $TECHNICAL_USER_NAME"
#=====
sudo useradd -m -s /bin/bash -G sudo $TECHNICAL_USER_NAME
sudo tee /etc/sudoers.d/$TECHNICAL_USER_NAME > /dev/null <<EOF
$TECHNICAL_USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL
EOF
sudo chmod 440 /etc/sudoers.d/$TECHNICAL_USER_NAME
sudo mkdir -p /home/$TECHNICAL_USER_NAME/.ssh
if [ $CURRENT_USER_NAME == 'root' ]; then
  sudo cp /$CURRENT_USER_NAME/.ssh/authorized_keys /home/$TECHNICAL_USER_NAME/.ssh/authorized_keys
else
  sudo cp /home/$CURRENT_USER_NAME/.ssh/authorized_keys /home/$TECHNICAL_USER_NAME/.ssh/authorized_keys
fi
sudo chmod 700 /home/$TECHNICAL_USER_NAME/.ssh
sudo chmod 600 /home/$TECHNICAL_USER_NAME/.ssh/authorized_keys
sudo chown -R $TECHNICAL_USER_NAME:$TECHNICAL_USER_NAME /home/$TECHNICAL_USER_NAME/.ssh
#=====

info "Конфигурирование sshd"
#=====
sudo tee /etc/ssh/sshd_config > /dev/null <<EOF
Include /etc/ssh/sshd_config.d/*.conf
Port $SSH_PORT
ListenAddress 0.0.0.0
PermitRootLogin no
MaxAuthTries 3
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_* COLORTERM NO_COLOR
Subsystem	sftp	/usr/lib/openssh/sftp-server
EOF
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
#=====

info "Отключение предустановленных фаерволов"
#=====
sudo systemctl stop nftables
sudo systemctl disable nftables
sudo systemctl stop ufw
sudo systemctl disable ufw
#=====

info "Подготовка ядра Linux"
#=====
sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sudo sysctl -w net.ipv4.ip_forward=1
#=====

info "Установка kubernetes, cri-o, helm"
#=====
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$KUBERNETES_VERSION/deb/Release.key" \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/cri-o-apt-keyring.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$KUBERNETES_VERSION/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/cri-o.list > /dev/null
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key" \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list > /dev/null
sudo apt update
sudo apt install -y cri-o
sudo systemctl enable crio
sudo systemctl start crio
sudo apt install -y kubelet kubeadm kubectl
sudo systemctl enable kubelet
sudo apt install -y helm
#=====