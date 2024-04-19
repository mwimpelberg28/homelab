kubeadm init --pod-network-cidr 172.18.0.0/16
kubectl apply -f canal.yml
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


