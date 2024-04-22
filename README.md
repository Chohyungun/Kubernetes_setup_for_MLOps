## Kubernetes 환경 셋업 가이드 
Kubernetes를 활용하여 MLOps를 구축하는 과정을 수행하는 과정에서, 환경 셋업 과정을 작성하였습니다.

MLOps 파이프라인을 구축하는 자세한 내용은 원본 노션 페이지를 참고해주세요.
- [원본 노션 페이지](https://www.notion.so/Tutorial-Kubernetes-MLOps-0cb15dc18dd1424b85af4356e315e2f1)

### 참고자료
- [MLOps for ALL](https://jlcan.github.io/mlops-for-all.github.io/)


**수행 환경**

- NVIDIA-Driver 이외에 단 하나라도 버전이 맞지 않는다면 원활한 구축이 힘듭니다

|  | Software | Version | 비고 |
| --- | --- | --- | --- |
| 클러스터 | Ubuntu | 20.04.3 LTS |  |
|  | Docker (Server) | 20.10.11 |  |
|  | NVIDIA-Driver | 470.86 | Optional |
|  | Kubernetes | v1.21.7 |  |
|  | Kubeflow | v1.4.0 |  |
|  | MLFlow | v1.21.0 |  |
|  | WSL | v2.0.14.0 |  |
| Helm Chart 써드파티 | datawire/ambassador | 6.9.3 |  |
|  | seldonio/seldon-core-operator | 1.11.2 |  |
| 클라이언트 | kubectl | v1.21.7 |  |
|  | helm | v3.7.1 |  |
|  | kustomize | v3.10.0 |  |
- 내부 소프트웨어가 각자 어떤 역할을 하는지, 그 소프트웨어의 대체재로 어떤 소프트웨어를 사용할 수 있을지는 아래의 레퍼런스를 통해 확인하실 수 있습니다.
    
    [[Ref] MLOps 내부 구성 요소 파악](https://www.notion.so/Ref-MLOps-d0352b34d02a47598368986f73cdce5c?pvs=21) 
    

## Kubernetes 실습 환경 구축

<aside>
⚠️ **짚고 넘어갈 점**
1. v0.1 기준 튜토리얼 과정은,  MLOps 환경에 대한 아무런 준비가 되어 있지 않다고 가정하여, 모든 소프트웨어를 터미널 창에서  하나하나 설치합니다. 추후 문서의 버전을 업그레이드 하면서 최종적으로는 도커 이미지 파일을 통해 MLOps 환경을 간편하게 빌드할 수 있도록 하겠습니다.
2. 본 문서에서는 Minikube를 통한 Kubertenes 환경을 구축합니다. 추후 문서의 버전을 업그레이드 하며 K3s, Kubeadm, k8s 환경에서도 동일한 환경을 구축할 수 있도록 하고, 최종적으로는 kubernetes 이외의 다른 애플리케이션을 활용하여 MLOps 환경을 구축하겠습니다.

</aside>

### 1. WSL을 활용한 Ubuntu 및 Python 가상 환경 설정

1. `vscode` 터미널에서 다음을 실행하여 wsl을 install 합니다
    
    ```bash
    wsl --install
    wsl --set-default-version 2
    ```
    
    <aside>
    ⚠️ 여기까지는 windows 환경의 터미널이고, 이제부터는 wsl을 통한 리눅스 환경을 접속한 뒤의 터미널입니다.
    
    </aside>
    
2. linux 환경으로 원격 접속이 완료었다면 이제 WSL 환경에서 파이썬 개발 환경을 구축하고, 가상환경을 실행합니다
    
    ```bash
    sudo apt update && sudo apt upgrade
    sudo apt-get install -y socat # 소켓을 깔지 않으면 kubectl를 사용하실 수 없습니다
    sudo apt install python3-pip python3-venv libmysqlclient-dev # 파이썬 가상환경은 생략하셔도 무관합니다
    source <project_name>/bin/activate
    ```
    

### 2. 클러스터 및 클라이언트 컴포넌트 환경 설정

**클러스터 컴포넌트**

- 도커 설치에 필요한 APT 패키지들을 설치합니다
    - 원활한 작업을 위해 최신 버전이 아닌 지정된 버전의 도커를 설치해야 합니다
    
    ```bash
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # 도커의 공식 GPG key를 추가합니다.
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # apt 패키지 매니저로 도커를 설치할 때, stable Repository에서 받아오도록 설정합니다.
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 5:20.10.11~3-0~ubuntu-focal 버전의 docker를 설치합니다
    sudo apt-get install -y containerd.io docker-ce=5:20.10.11~3-0~ubuntu-focal docker-ce-cli=5:20.10.11~3-0~ubuntu-focal
    
    # 도커가 정상적으로 설치된 것을 확인합니다
    sudo docker run hello-world
    
    # sudo 키워드 없이 사용 가능하도록 docker에 command 사용 권한 부여
    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker
    ```
    
- 메모리 스왑: **클러스터** 노드에서 swap이라고 불리는 가상메모리를 꺼 두어야 합니다. 다음 명령어를 통해 swap을 꺼 둡니다
    - **클러스터와 클라이언트를 같은 데스크톱에서 사용할 때 swap 메모리를 종료하면 속도의 저하가 있을 수 있습니다…**
    
    ```bash
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo swapoff -a
    ```
    

**클라이언트 컴포넌트**

1. Kubectl 설치
    
    <aside>
    💡 **Kubectl란?**
    개발자나 시스템 관리자가 커맨드 라인을 통해 Kubernetes 클러스터와 상호 작용 역할을 하는 클라이언트 전용 도구입니다.
    
    </aside>
    
    ```bash
    # WSL 사용자일 경우입니다
    curl -LO https://dl.k8s.io/release/v1.21.7/bin/linux/amd64/kubectl
    
    # root로 파일 권한 및 위치 변경
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    ```
    

### 3. Kubernetes 내부 클러스터 설치

**Kubernetes 애플리케이션 환경**

1. Minikube 설치
    
    <aside>
    💡 **Minikube란?**
    개발자나 시스템 관리자가 커맨드 라인을 통해 Kubernetes 클러스터와 상호 작용 역할을 하는 클라이언트 전용 도구입니다.
    
    </aside>
    
    ```bash
    wget https://github.com/kubernetes/minikube/releases/download/v1.24.0/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    
    # 쿠버네티스 버전은 반드시 1.22 이전 버전이어야 합니다
    minikube start --driver=none \
      --kubernetes-version=v1.21.7 \
      --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
      --extra-config=apiserver.service-account-issuer=kubernetes.default.svc
    ```
    
    <aside>
    ⚠️ **WSL 사용시 유의점**
    
    - wsl2는 기본적으로 `systemctl`을 제공하지 않아 minikube 설치에 어려움을 겪을 수 있습니다 아래 코드를 반드시 `minikube` 설치 전에 적용하여 `systemctl` 를 설치하여 주세요
    
    ```bash
    wget https://github.com/arkane-systems/genie/releases/download/v2.5/systemd-genie_2.5_amd64.deb
    sudo dpkg -i systemd-genie_2.5_amd64.deb
    sudo apt-get install -f
    sudo sysctl fs.protected_regular=0
    genie -s
    ```
    
    </aside>
    
    ```bash
    # mini kube의 defalt addon을 비활성화합니다, 추후 의존성 문제가 발생 할 수 있습니다
    minikube addons disable storage-provisioner
    minikube addons disable default-storageclass
    ```
    
2. 클라이언트 셋업
    
    <aside>
    ⚠️ 반드시 root user로 작업을 진행해야 합니다.
    
    </aside>
    
    - 클러스터에서 config를 확인한 후 클라이언트 노드에서 .kube 폴더를 생성하여 config 정보를 저장합니다
        
        ```bash
        # 클러스터 config 확인
        minikube kubectl -- config view --flatten
        
        # 클라이언트 노드
        mkdir -p /home/$USER/.kube
        # vim 에디터 사용
        vi /home/$USER/.kube/config
        
        # config 붙여넣기 완료 후 :wq
        ```
        
        - config 예시
            
            ```bash
            apiVersion: v1
            clusters:
            - cluster:
                certificate-authority-data:<~~>
                extensions:
                - extension:
                    last-update: Sat, 20 Apr 2024 16:56:50 KST
                    provider: minikube.sigs.k8s.io
                    version: v1.24.0
                  name: cluster_info
                server: https://172.21.111.109:8443
              name: minikube
            contexts:
            - context:
                cluster: minikube
                extensions:
                - extension:
                    last-update: Sat, 20 Apr 2024 16:56:50 KST
                    provider: minikube.sigs.k8s.io
                    version: v1.24.0
                  name: context_info
                namespace: default
                user: minikube
              name: minikube
            current-context: minikube
            kind: Config
            preferences: {}
            users:
            - name: minikube
              user:
                client-certificate-data: <~~>
                client-key-data: <~~>
            ```
            
            <aside>
            ⚠️ **control-plane**의 버전을 주의 깊게 확인해주세요
            버전이 1.22 이상일 경우 내부 클러스터 pod와 namespace 설치 시 문제가 발생합니다.
            
            </aside>
            
            <aside>
            💡 **Control plane란?**
            클러스터의 모든 주요 결정과 작업 스케줄링, 클러스터 상태 유지 등을 담당하는 클러스터의 관리 센터를 지칭합니다.
            
            </aside>
            

### 4. Kubernetes 모듈 설치

1. Helm 설치
    
    <aside>
    💡 **Helm이란?**
    Kubernetes에서 패키지와 관련된 자원을 한 번에 배포하고 관리할 수 있게 도와주는 패키지 매니징 도구입니다.
    
    </aside>
    
    ```bash
    wget https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz
    tar -zxvf helm-v3.7.1-linux-amd64.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    ```
    
2. Kustomize 설치
    
    <aside>
    💡 **Kustomize란?**
    Kubernetes에서 패키지와 관련된 자원을 한 번에 배포하고 관리할 수 있게 도와주는 패키지 매니징 도구입니다.
    
    </aside>
    
    ```bash
    # kustomize v3.10.0 버전 설치: 해당 버전 이상의 버전을 설치 할 경우 호환 문제 발생
    wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.10.0/kustomize_v3.10.0_linux_amd64.tar.gz
    tar -zxvf kustomize_v3.10.0_linux_amd64.tar.gz
    sudo mv kustomize /usr/local/bin/kustomize
    ```
    
3. CSI 플러그인 설치
    
    <aside>
    💡 **CSI(Container Storage Interface) 플러그인이란?**
    Kubernetes의 표준 인터페이스를 통해 다양한 스토리지 시스템을 클러스터에 연결하는 역할을 수행하는 모듈입니다.
    
    </aside>
    
    - Local Path Provisioner 설치
        
        <aside>
        💡 **Local Path Provisioner란?**
        단일 노드 클러스터 등 로컬 노드의 스토리지를 활용하여 간단하게 퍼시스턴트 볼륨을 생성 및 관리하는 CSI 플러그인의 구성요소 중 하나입니다.
        
        </aside>
        
        ```bash
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.20/deploy/local-path-storage.yaml
        kubectl -n local-path-storage get pod
        ```
        
    - Pod의 Running을 확인 후 default storage class로 변경
        
        <aside>
        💡 **Storage class란?**
        스토리지 성능, 복제, 백업 정책과 같은 프로비저너의 설정과 관련된 정책을 정의하는 클래스입니다.
        
        </aside>
        
        ```bash
        kubectl patch storageclass local-path  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        ```
        

### 5. Kubeflow 및 내 컴포넌트 설치

<aside>
💡 **Kubeflow란?**
Kubeflow는 머신러닝 워크플로를 Kubernetes 상에서 쉽게 배포하고 관리할 수 있도록 설계된 오픈 소스 플랫폼입니다.

</aside>

- Kubeflow를 설치하기 위하여 설치에 필요한 manifests 파일들을 준비합니다
    
    <aside>
    💡 **Manifests란?**
    Kubeflow 컴포넌트를 Kubernetes 클러스터에 설치하고 구성하는 데 필요한 설정 파일과 템플릿의 모음으로, Kubernetes에서 컨테이너화된 애플리케이션을 배포, 관리, 운영하기 위한 YAML 파일로 구성되어 있습니다.
    
    </aside>
    
    ```bash
    git clone -b v1.4.0 https://github.com/kubeflow/manifests.git
    cd manifests
    ```
    
- 설치해야 할 컴포넌트들은 다음과 같습니다
    
    
    | 컴포넌트 | 설명 |
    | --- | --- |
    | Cert-manager | Kubernetes에서 TLS 인증서를 자동으로 발급하고 관리하는 도구 |
    | Istio | 마이크로서비스 간 통신을 제어하고 보안을 강화하는 서비스 메쉬 |
    | Dex | OpenID Connect (OIDC) 기반의 인증 제공자 |
    | OIDC AuthService | OIDC 기반 인증을 수행하는 Kubeflow 서비스 |
    | Kubeflow Namespace | Kubeflow 컴포넌트를 격리하여 배포하는 네임스페이스 |
    | Kubeflow Roles | Kubeflow 사용자 및 서비스에 대한 역할 및 권한 설정 |
    | Kubeflow Istio Resources | Istio 정책을 사용하여 Kubeflow 서비스의 트래픽 관리 |
    | Kubeflow Pipelines | 데이터 과학 워크플로의 컴포넌트화 및 재사용을 가능하게 하는 도구 |
    | Katib | Kubernetes에서 자동 머신러닝 실험을 관리하는 시스템 |
    | Central Dashboard | Kubeflow의 중앙 집중식 웹 UI |
    | Admission Webhook | 리소스 생성 또는 수정 시 정책을 강제하는 동적 검사 도구 |
    | Notebooks & Jupyter Web App | Jupyter 노트북을 쉽게 생성하고 관리할 수 있는 웹 애플리케이션 |
    | Profiles + KFAM | 사용자 프로파일 관리 및 멀티-테넌시 지원 |
    | Volumes Web App | 사용자가 데이터 볼륨을 쉽게 생성하고 관리할 수 있는 웹 애플리케이션 |
    | Tensorboard & Tensorboard Web App | 텐서보드 로깅 데이터를 시각화하는 도구 및 그 웹 인터페이스 |
    | Training Operator | 다양한 머신러닝 트레이닝 프레임워크를 쿠버네티스 상에서 관리 |
    | User Namespace | 각 사용자가 리소스를 격리하여 사용할 수 있는 네임스페이스 |
    
    <aside>
    ⚠️ 클러스터 내부의 자세한 설명은 상단의 구성요소 레퍼런스 파일을 통해 확인해주시길 바랍니다.
    
    </aside>
    
    - Pod간 의존하는 경우가 많기 때문에 하나씩 설치하여 running 여부를 살펴보는 것을 추천드립니
    
    ```bash
    # 반드시 클러스터 설치 후 모든 pod가 running 상태임을 확인해야 합니다
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
    ```
    
    - 클러스터 상태 확인 코드로 39개의 Pod가 모두 Running이 되기를 기다립니다
        
        ```bash
        kubectl get po -n kubeflow
        ```
        
    - 모두 Running 상태가 되었다면 ml-pipline UI를 열어 화면을 확인해봅니다
        
        ```bash
        ## 보안상 문제 없을경우 localhost를 사용합니다
        # MLPipline UI
        kubectl port-forward --address 0.0.0.0 svc/ml-pipeline-ui -n kubeflow 8888:80
        # katib UI
        kubectl port-forward svc/katib-ui -n kubeflow 8081:80
        # Central Dashboard UI
        kubectl port-forward svc/centraldashboard -n kubeflow 8082:80
        # All component UI
        kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
        ```
        
        - 방화벽 설정으로 접속해 모든 tcp 프로토콜의 포트에 대한 접속을 허가 또는 8888번 포트의 접속 허가를 추가해 접근 권한을 허가해줍니다.
        - Email Address: `user@example.com`
        - Password: `12341234`

### 6. MLflow 트래킹 서버 환경설정

1. PostgreSQl DB 설치
    - MLflow Tracking Server가 Backend Store로 사용할 용도의 PostgreSQL DB를 쿠버네티스 클러스터에 배포합니다
    
    ```bash
    # mlflow-system 이름으로 namespace 생성
    kubectl create ns mlflow-system
    ```
    
2. MiniO 설정
    
    <aside>
    💡 **MiniO란?**
    오픈소스로 제공되는 분산 스토리지 솔루션입니다 AWS S3(Simple Storage Service)와 호환되는 API를 제공하여, 프라이빗 클라우드 환경에서 S3와 같은 스토리지 기능을 구현할 때 널리 사용됩니다.
    
    </aside>
    
    ```bash
    kubectl port-forward svc/minio-service -n kubeflow 9000:9000
    ```
    
    - Username: `minio`
    - Password: `minio123`
    
    
    우측 하단의 **`+`** 버튼을 클릭하여, `Create Bucket`를 클릭합니다.
    
3. Helm Repository 추가
    
    ```bash
    helm repo add mlops-for-all https://mlops-for-all.github.io/helm-charts
    helm repo update
    helm install mlflow-server mlops-for-all/mlflow-server \
      --namespace mlflow-system \
      --version 0.2.0
    kubectl port-forward svc/mlflow-server-service -n mlflow-system 5000:5000
    ```
    

### 7. Seldon-Core 설치

<aside>
💡 **Seldon Core란?**
대규모로 Kubernetes 환경에서 머신러닝 모델을 배포할 수 있는 오픈소스 플랫폼입니다

</aside>

- Seldon-Core를 사용하기 위해서는 쿠버네티스의 인그레스(Ingress)를 담당하는 Ambassador 와 Istio 와 같은 모듈이 필요합니다
    - Ambassador vs Istio는 상기 언급 레퍼런스를 통해 확인하실 수 있습니다.
- Ambassador 설치
    
    ```bash
    helm repo add datawire https://www.getambassador.io
    helm repo update
    helm install ambassador datawire/ambassador \
      --namespace seldon-system \
      --create-namespace \
      --set image.repository=quay.io/datawire/ambassador \
      --set enableAES=false \
      --set crds.keep=false \
      --version 6.9.3
      
    helm install seldon-core seldon-core-operator \
        --repo https://storage.googleapis.com/seldon-charts \
        --namespace seldon-system \
        --set usageMetrics.enabled=true \
        --set ambassador.enabled=true \
        --version 1.11.2
    ```
    

### 8. Prometheus & Grafana 설치

<aside>
💡 **Prometheus, Grafana란?**
프로메테우스는 다양한 대상으로부터 Metric을 수집하는 도구이며, 그라파나는 모인 데이터를 시각화하는 것을 도와주는 도구입니다.

</aside>

```bash
helm repo add seldonio https://storage.googleapis.com/seldon-charts
helm repo update
helm install seldon-core-analytics seldonio/seldon-core-analytics \
  --namespace seldon-system \
  --version 1.12.0

kubectl port-forward svc/seldon-core-analytics-grafana -n seldon-system 8090:80
```

- 웹 브라우저를 열어 [localhost:8090](http://localhost:8090/)으로 접속합니다
    
    
    - Email or username : `admin`
    - Password : `password`
    
    
- 좌측의 대시보드 아이콘을 클릭하여, `Manage` 버튼을 클릭하여 기본적인 그라파나 대시보드가 포함되어있는 것을 확인하고, 이 중 `Prediction Analytics` 대시보드를 클릭하여 `Seldon-Core` 에서 생성한 `SeldonDeployment`의 Metrics을 확인합니다
      
