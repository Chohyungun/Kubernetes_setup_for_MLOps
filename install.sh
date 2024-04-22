# 스크립트 오류 발생 시 중단
set -e

# 필요한 소프트웨어 설치
echo "WSL 및 필수 패키지 설치를 시작합니다..."
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y socat docker.io python3-pip python3-venv libmysqlclient-dev ca-certificates curl gnupg lsb-release

# Docker 설정
echo "Docker 설치 및 설정..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install -y containerd.io docker-ce=5:20.10.11~3-0~ubuntu-focal docker-ce-cli=5:20.10.11~3-0~ubuntu-focal
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker

# Swap 비활성화
echo "Swap 비활성화..."
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# Kubernetes 클라이언트 도구 설치
echo "Kubectl 설치..."
curl -LO https://dl.k8s.io/release/v1.21.7/bin/linux/amd64/kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Minikube 설치
echo "Minikube 설치..."
wget https://github.com/kubernetes/minikube/releases/download/v1.24.0/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start --driver=none \
  --kubernetes-version=v1.21.7 \
  --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
  --extra-config=apiserver.service-account-issuer=kubernetes.default.svc

# 필요 도구 Helm, Kustomize 설치
echo "Helm 및 Kustomize 설치..."
wget https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz
tar -zxvf helm-v3.7.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm

wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.10.0/kustomize_v3.10.0_linux_amd64.tar.gz
tar -zxvf kustomize_v3.10.0_linux_amd64.tar.gz
sudo mv kustomize /usr/local/bin/kustomize

# Kubeflow 및 관련 컴포넌트 설치
echo "Kubeflow 및 관련 컴포넌트 설치..."
git clone -b v1.4.0 https://github.com/kubeflow/manifests.git
cd manifests
kustomize build common/cert-manager/cert-manager/base | kubectl apply -f -
kustomize build common/cert-manager/kubeflow-issuer/base | kubectl apply -f -
kustomize build common/istio-1-9/istio-crds/base | kubectl apply -f -
kustomize build common/cert-manager/kubeflow-issuer/base | kubectl apply -f -
kustomize build common/istio-1-9/istio-crds/base | kubectl apply -f -
kustomize build common/istio-1-9/istio-namespace/base | kubectl apply -f -
kustomize build common/istio-1-9/istio-install/base | kubectl apply -f -
kustomize build common/dex/overlays/istio | kubectl apply -f -
kustomize build common/oidc-authservice/base | kubectl apply -f -
kustomize build common/kubeflow-namespace/base | kubectl apply -f -
kustomize build common/kubeflow-roles/base | kubectl apply -f -
kustomize build common/istio-1-9/kubeflow-istio-resources/base | kubectl apply -f -
kustomize build apps/pipeline/upstream/env/platform-agnostic-multi-user | kubectl apply -f -
kustomize build apps/katib/upstream/installs/katib-with-kubeflow | kubectl apply -f -
kustomize build apps/centraldashboard/upstream/overlays/istio | kubectl apply -f -
kustomize build apps/admission-webhook/upstream/overlays/cert-manager | kubectl apply -f -
kustomize build apps/jupyter/notebook-controller/upstream/overlays/kubeflow | kubectl apply -f -
kustomize build apps/jupyter/jupyter-web-app/upstream/overlays/istio | kubectl apply -f -
kustomize build apps/profiles/upstream/overlays/kubeflow | kubectl apply -f -
kustomize build apps/volumes-web-app/upstream/overlays/istio | kubectl apply -f -
kustomize build apps/tensorboard/tensorboards-web-app/upstream/overlays/istio | kubectl apply -f -
kustomize build apps/tensorboard/tensorboard-controller/upstream/overlays/kubeflow | kubectl apply -f -
kustomize build apps/training-operator/upstream/overlays/kubeflow | kubectl apply -f -
kustomize build common/user-namespace/base | kubectl apply -f -
kubectl get all -n kubeflow

# 아래 내용은 kubectl get all -n kubeflow 결과로 모든 컴포넌트가 RUNNING 상태일때 수행하시는 것을 추천드립니다.

# mlflow-system 이름으로 namespace 생성
kubectl create ns mlflow-system
echo "MLflow 트래킹 서버 설정을 시작합니다..."
kubectl create ns mlflow-system


# Helm 리포지토리 추가 및 MLflow 서버 설치
helm repo add mlops-for-all https://mlops-for-all.github.io/helm-charts
helm repo update
helm install mlflow-server mlops-for-all/mlflow-server --namespace mlflow-system --version 0.2.0

# Seldon-Core 설치
echo "Seldon-Core 설치를 시작합니다..."
helm repo add datawire https://www.getambassador.io
helm repo update
helm install ambassador datawire/ambassador --namespace seldon-system --create-namespace --set image.repository=quay.io/datawire/ambassador --set enableAES=false --set crds.keep=false --version 6.9.3
helm install seldon-core seldon-core-operator --repo https://storage.googleapis.com/seldon-charts --namespace seldon-system --set usageMetrics.enabled=true --set ambassador.enabled=true --version 1.11.2

# Prometheus & Grafana 설치
echo "Prometheus & Grafana 설치를 시작합니다..."
helm repo add seldonio https://storage.googleapis.com/seldon-charts
helm repo update
helm install seldon-core-analytics seldonio/seldon-core-analytics --namespace seldon-system --version 1.12.0
