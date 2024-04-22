# [Tutorial] Kubernetes를 통한 MLOps 시스템 구축

- 2024-04-19 v0.1 - 초안 (조현건)
- 2024-04-20 v0.2 - 초안 보완(조현건)
- 2024-04-22 v0.3 - 초안 보완(조현건)

컨테이너 오케스트레이션의 대표적인 애플리케이션 Kubernetes를 통한 MLOps 시스템을 구축하는 하는 방법을 다룹니다. 

### 다룰 내용

1. Kubernetes 실습 환경 구축
2. MLOps 시스템 구축을 위한 컴포넌트 연동
3. 컴포넌트 작성을 통한 파이프라인 구축
4. 생성한 MLOps 파이프라인의 배포

### 참고자료

- [MLOps for ALL](https://jlcan.github.io/mlops-for-all.github.io/)

## 개요

MLOps를 공부하는 데 있어서 가장 큰 장벽은 MLOps 시스템을 구성해보고 사용해보기가 어렵다는 점입니다. AWS, GCP 등의 퍼블릭 클라우드 혹은 Weight & Bias, neptune.ai 등의 상용 툴을 사용해보기에는 과금에 대한 부담이 존재하고, 처음부터 모든 환경을 혼자서 구성하기에는 어디서부터 시작해야 할지 막막하게 느껴질 수밖에 없습니다.

이러한 이유로 우분투가 설치되는 데스크톱 하나만 준비되어 있다면 MLOps 시스템을 밑바닥부터 구축하고 사용할 수 있는 오픈소스 애플리케이션을 연동하여 MLOps 환경을 구축하고 배포하는 과정을 수행하는 튜토리얼을 작성하였습니다.

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
            
            ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled.png)
            
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
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%201.png)
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%202.png)
    
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
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%203.png)
    

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

- 웹 브라우저를 열어 [localhost:8090](http://localhost:8090/)으로 접속하면 다음과 같은 화면이 출력됩니다.
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%204.png)
    
    - Email or username : `admin`
    - Password : `password`
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%205.png)
    
- 좌측의 대시보드 아이콘을 클릭하여, `Manage` 버튼을 클릭하여 기본적인 그라파나 대시보드가 포함되어있는 것을 확인하고, 이 중 `Prediction Analytics` 대시보드를 클릭하여 `Seldon-Core` 에서 생성한 `SeldonDeployment`의 Metrics을 확인합니다
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%206.png)
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%207.png)
    

## Kubeflow를 활용한 MLOps 파이프라인 설계

<aside>
⚠️ 본 문서는 Kubeflow Pipeline을 MlOps를 구성하는 구성요소로써 활용합니다. Kubeflow 개념은 하단의 레퍼런스 페이지를 통해 확인해주시길 바랍니다.

</aside>

[Kubeflow 개념](https://www.notion.so/Kubeflow-08df99c47f9240af94c2a1aa9459b94d?pvs=21)

### Component Write

컴포넌트(Component)를 작성하기 위해서는 다음과 같은 내용을 작성해야 합니다.

1. 컴포넌트 콘텐츠(Component Contents) 작성
2. 컴포넌트 래퍼(Component Wrapper) 작성

**Component Contents**[](https://jlcan.github.io/mlops-for-all.github.io/docs/kubeflow/basic-component#component-contents)

Kubeflow에서 컴포넌트 콘텐츠는 반드시 Config로 정의하고, Config들은 컴포넌트 래퍼에서 전달이 되어야 합니다.

**Component Wrapper**

콘텐츠에서 필요한 Config를 래퍼의 argument로 추가합니다. 다음과 같이 argument와 그 타입, 그리고 반환하는 타입을 적어서 컴포넌트 래퍼를 완성합니다

```python
from typing import NamedTuple
# 컴포넌트를 kubeflow에서 사용할 수 있는 포맷으로 변환하는 라이브러리
from kfp.components import create_component_from_func

## 입력받은 숫자를 2로 나눈 몫과 나머지를 반환하는 컴포넌트
# 컴포넌트를 kubeflow에서 사용할 수 있는 포맷으로 변환
@create_component_from_func
def divide_and_return_number(
    number: int,
) -> NamedTuple("DivideOutputs", [("quotient", int), ("remainder", int)]): # Type 힌트
    from collections import namedtuple

    quotient, remainder = divmod(number, 2)
    print("quotient is", quotient)
    print("remainder is", remainder)

    divide_outputs = namedtuple(
        "DivideOutputs",
        [
            "quotient",
            "remainder",
        ],
    )
    return divide_outputs(quotient, remainder)
    
    # 파이썬 코드로 공유를 할 수 없는 경우 YAML 파일로 컴포넌트를 공유해서 사용
    if __name__ == "__main__":
    print_and_return_number.component_spec.save("divide_and_return_number.yaml")
```

생성된 파일을 공유해서 파이프라인에서 다음과 같이 사용 가능

```python
from kfp.components import load_component_from_file

print_and_return_number = load_component_from_file("divide_and_return_number.yaml")
```

<aside>
⚠️ **Argument 만을 적는 것이 아니라, argument의 타입 힌트도 작성해야 합니다.** 
Kubeflow에서는 파이프라인을 Kubeflow 포맷으로 변환할 때, 컴포넌트 간의 연결에서 정해진 입력과 출력의 타입이 일치하는지 체크합니다. 만약 컴포넌트가 필요로 하는 입력과 다른 컴포넌트로부터 전달받은 출력의 포맷이 일치하지 않을 경우 파이프라인 생성을 할 수 없습니다.

</aside>

### Kubeflow component 실행[](https://jlcan.github.io/mlops-for-all.github.io/docs/kubeflow/basic-component#how-kubeflow-executes-component)

Kubeflow에서 컴포넌트가 실행되는 순서는 다음과 같습니다.

1. `docker pull <image>`: 정의된 컴포넌트의 실행 환경 정보가 담긴 이미지를 pull
2. run `command`: pull 한 이미지에서 컴포넌트 콘텐츠를 실행합니다.

### Pipeline Write

컴포넌트는 독립적으로 실행되지 않고 파이프라인의 구성요소로써 실행됩니다. 따라서 컴포넌트를 실행해 보려면 파이프라인을 작성해야 합니다. 그리고 파이프라인을 작성하기 위해서는 컴포넌트의 집합과 컴포넌트의 실행 순서가 필요합니다.

아래 그림의 과정을 구현하기 위한 컴포넌트 집합과, 실행 순서를 코드로 구현하면 다음과 같습니다

![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%208.png)

```python
import kfp
from kfp.components import create_component_from_func
from kfp.dsl import pipeline

@create_component_from_func
def print_and_return_number(number: int) -> int:
print(number)
return number

@create_component_from_func
def sum_and_print_numbers(number_1: int, number_2: int):
print(number_1 + number_2)

# 각 컴포넌트에 필요한 Config들을 모아 파이프라인 Config로 정의, kubeflow 사용 형식으로 변환
@pipeline(name="example_pipeline")
def example_pipeline(number_1: int, number_2: int):
number_1_result = print_and_return_number(number_1)
number_2_result = print_and_return_number(number_2)
sum_result = sum_and_print_numbers(
number_1=number_1_result.output, number_2=number_2_result.output
) # 두 값의 결과를 sum_and_print_numbers 에 전달

if **name** == "**main**":
kfp.compiler.Compiler().compile(example_pipeline, "example_pipeline.yaml")
```

1. `print_and_return_number`
    
    입력받은 숫자를 출력하고 반환하는 컴포넌트입니다.
    
    컴포넌트가 입력받은 값을 반환하기 때문에 int를 return의 타입 힌트로 입력합니다.
    
2. `sum_and_print_numbers`
    
    입력받은 두 개의 숫자의 합을 출력하는 컴포넌트입니다.
    
    이 컴포넌트 역시 두 숫자의 합을 반환하기 때문에 int를 return의 타입 힌트로 입력합니다.
    

### Pipeline Upload

코드의 결과 값으로 도출된 yaml 파일을 활용하여 파이프라인을 직접 kubeflow에서 업로드 합니다

```python
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```

코드 실행 후 [http://localhost:8080](http://localhost:8080/)에 접속해 대시보드를 열어 아래의 과정을 수행합니다

1. **Pipelines** 탭 선택
2. **Upload Pipline** 선택
3.  **Choose file** 선택
4.  생성된 yaml 파일 업로드

![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%209.png)

**Pipeline Version 관리**

업로드된 파이프라인은 업로드를 통해서 버전을 관리할 수 있습니다. 위의 예시에서 파이프라인을 업로드한 경우 다음과 같이 example_pipeline이 생성된 것을 확인할 수 있습니다.

![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2010.png)

파이프라인을 클릭하여 파이프라인의 그래프를 확인하고, Upload Version을 클릭하여 파이프라인을 업로드할 수 있는 화면을 띄워, 파이프라인을 업로드 합니다.

![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2011.png)

### **Pipeline Run**

아래 과정을 통해 업로드한 파이프라인을 실행시킵니다.

1. Create Experiment
    
    <aside>
    💡 **Experiment란?**
    Kubeflow 에서 실행되는 Run을 논리적으로 관리하는 단위입니다. Kubeflow에서 namespace를 처음 들어오면 생성되어 있는 Experiment가 없습니다. 따라서 파이프라인을 실행하기 전에 미리 Experiment를 생성해두어야 합니다.
    
    </aside>
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2012.png)
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2013.png)
    
2. Run Pipline
    1. Create Run 선택
    2. Experiment 선택
        - Create Experiment 단계에 설정한 Experiment로 선택
    3. Pipeline Config 입력
        - 업로드한 파이프라인은 number_1과 number_2를 입력
    4. Start
3. Result 확인
    
    Runs 탭에서 확인 가능
    
    - 실행 전
        
        ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2014.png)
        
    - 실행 완료
        
        ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2015.png)
        

## **Component - InputPath/OutputPath**

kubeflow에서 컴포넌트들은 각각 컨테이너 위에서 서로 독립적으로 실행됩니다. 즉, 같은 메모리를 공유하고 있지 않기 때문에, 보통의 파이썬 함수에서 사용하는 방식과 같이 객체를 전달할 수 없습니다.

컴포넌트 간에 넘겨 줄 수 있는 정보는 `json` 으로만 가능하기 때문에, Model이나 DataFrame과 같이 json 형식으로 변환할 수 없는 타입의 객체는 메모리 대신 파일에 데이터를 저장한 뒤, 그 파일을 이용해 정보를 전달하는 방법을 통해 전달되어야 합니다

```python
from kfp.components import InputPath, OutputPath

# Component Wrapper
def train_from_csv(
		# kubeflow 입력과 출력의 경로와 관련된 매직
    train_data_path: InputPath("csv"), 
    train_target_path: InputPath("csv"),
    model_path: OutputPath("dill"),
    kernel: str,
): # Component Contnent
    import dill
    import pandas as pd

    from sklearn.svm import SVC

    train_data = pd.read_csv(train_data_path)
    train_target = pd.read_csv(train_target_path)

    clf = SVC(kernel=kernel)
    clf.fit(train_data, train_target)

    with open(model_path, mode="wb") as file_writer:
        dill.dump(clf, file_writer)
```

이렇게 만든 후 파이프라인에서 서로 연결을 하면 kubeflow에서 필요한 경로를 자동으로 생성후 입력해 주기 때문에 더 이상 유저는 경로를 신경쓰지 않고 컴포넌트간의 관계만 신경쓰면 됩니다.

**InputPath/OutputPath Rule**

kubeflow에서 정한 법칙으로 `InputPath` 와 `OutputPath` 으로 생성된 경로들은 파이프라인에서 접근할 때는 `_path` 접미사를 생략하여 접근합니다

<aside>
⚠️ **Kubeflow는 쿠버네티스를 이용하기 때문에 컴포넌트 래퍼는 각각 독립된 컨테이너 위에서 컴포넌트 콘텐츠를 실행합니다.** 
따라서 kubernetes 환경과 Local 환경의 라이브러리 버전이 호환되지 않을 수 있습니다. 따라서`base_image` 또는 `package_to_install` 을 사용하여 패키지를 추가하여 버전을 업데이트합니다

</aside>

## **Pipeline Setting**

**Display Name**

생성된 파이프라인 내에서 컴포넌트는 두 개의 이름을 갖습니다

- task_name: 컴포넌트를 작성할 때 작성한 함수 이름
- display_name: kubeflow UI상에 보이는 이름
    - `set_display_name` attribute를 이용하여 이름 생성
        
        ```python
        # 이전 example_pipeline 코드에서 바뀐 부분만 작성
        @pipeline(name="example_pipeline")
        def example_pipeline(number_1: int, number_2: int):
            number_1_result = print_and_return_number(number_1).set_display_name("This is number 1")
            number_2_result = print_and_return_number(number_2).set_display_name("This is number 2")
            sum_result = sum_and_print_numbers(
                number_1=number_1_result.output, number_2=number_2_result.output
            ).set_display_name("This is sum of number 1 and number 2")
        
        if __name__ == "__main__":
            kfp.compiler.Compiler().compile(example_pipeline, "example_pipeline.yaml")
        ```
        

**Resource**

1. GPU 설정
    
    `set_gpu_limit()` attribute 이용해 설정
    
    - int 형으로 입력해야 함
2. CPU 설정
    
    `set_cpu_limit()` attribute 이용해 설정
    
    - string 형으로 입력해야 함
3. Memory 제한
    
    `set_gpu_limit()` attribute 이용해 설정
    

```python
# 이전 example_pipeline 코드에서 바뀐 부분만 작성
@pipeline(name="example_pipeline")
def example_pipeline(number_1: int, number_2: int):
    number_1_result = print_and_return_number(number_1).set_display_name("This is number 1")
    number_2_result = print_and_return_number(number_2).set_display_name("This is number 2")
    # GPU 사용: .gpu_limit(1)
    # CPU 사용: .set_cpu_limit("16")
    # Memory 제한: .set_memory_limit("1G")
    sum_result = sum_and_print_numbers(
        number_1=number_1_result.output, number_2=number_2_result.output
    ).set_display_name("This is sum of number 1 and number 2").set_gpu_limit(1).set_memory_limit("1G")
```

## **Run Result**

Run의 실행결과는 다음을 통해 확인 가능

1. **Graph**
    1. Input/Output[](https://jlcan.github.io/mlops-for-all.github.io/docs/kubeflow/advanced-run#inputoutput)
        
        Input/Output 탭은 컴포넌트에서 사용한 Config들과 Input, Output Artifacts를 확인하고 다운로드 받을 수 있습니다.
        
    2. Logs[](https://jlcan.github.io/mlops-for-all.github.io/docs/kubeflow/advanced-run#logs)
        
        Logs에서는 파이썬 코드 실행 중 나오는 모든 stdout을 확인할 수 있습니다. 다만 pod은 일정 시간이 지난 후 지워지기 때문에 일정 시간이 지나면 이 탭에서는 확인할 수 없습니다. 이때는 Output artifacts의 main-logs에서 확인할 수 있습니다.
        
    3. Visualizations[](https://jlcan.github.io/mlops-for-all.github.io/docs/kubeflow/advanced-run#visualizations)
        
        Visualizations에서는 컴포넌트에서 생성된 플랏을 보여줍니다.
        
        플랏을 생성하기 위해서는 `mlpipeline_ui_metadata: OutputPath("UI_Metadata")` argument로 보여주고 싶은 값을 저장하면 됩니다. 이 때 플랏의 형태는 html 포맷이어야 합니다. 
        
        ```python
        from functools import partial
        
        import kfp
        from kfp.components import create_component_from_func, OutputPath
        from kfp.dsl import pipeline
        
        @partial(
            create_component_from_func,
            packages_to_install=["matplotlib"],
        )
        def plot_linear(mlpipeline_ui_metadata: OutputPath("UI_Metadata")):
            import base64
            import json
            from io import BytesIO
        
            import matplotlib.pyplot as plt
        
            plt.plot([1, 2, 3], [1, 2, 3])
        
            tmpfile = BytesIO()
            plt.savefig(tmpfile, format="png")
            encoded = base64.b64encode(tmpfile.getvalue()).decode("utf-8")
        
            html = f"<img src='data:image/png;base64,{encoded}'>"
            metadata = {
                "outputs": [
                    {
                        "type": "web-app",
                        "storage": "inline",
                        "source": html,
                    },
                ],
            }
            with open(mlpipeline_ui_metadata, "w") as html_writer:
                json.dump(metadata, html_writer)
        
        @pipeline(name="plot_pipeline")
        def plot_pipeline():
            plot_linear()
        
        if __name__ == "__main__":
            kfp.compiler.Compiler().compile(plot_pipeline, "plot_pipeline.yaml")
        ```
        
        ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2016.png)
        
2. Run output
    
    kubeflow에서 지정한 형태로 생긴 Artifacts를 모아서 보여주는 곳이며 평가 지표(Metric)를 보여줍니다.
    
    ```python
    import kfp
    from kfp.components import create_component_from_func, OutputPath
    from kfp.dsl import pipeline
    
    @create_component_from_func
    def print_and_return_number(number: int) -> int:
        print(number)
        return number
    
    @create_component_from_func
    def sum_and_print_numbers(number_1: int, number_2: int) -> int:
        sum_number = number_1 + number_2
        print(sum_number)
        return sum_number
    
    @create_component_from_func
    def show_metric_of_sum(
        number: int,
        mlpipeline_metrics_path: OutputPath("Metrics"),
      ):
        import json
        metrics = {
            "metrics": [
                {
                    "name": "sum_value",
                    "numberValue": number,
                },
            ],
        }
        with open(mlpipeline_metrics_path, "w") as f:
            json.dump(metrics, f)
    
    @pipeline(name="example_pipeline")
    def example_pipeline(number_1: int, number_2: int):
        number_1_result = print_and_return_number(number_1)
        number_2_result = print_and_return_number(number_2)
        sum_result = sum_and_print_numbers(
            number_1=number_1_result.output, number_2=number_2_result.output
        )
        show_metric_of_sum(sum_result.output)
    
    if __name__ == "__main__":
        kfp.compiler.Compiler().compile(example_pipeline, "example_pipeline.yaml")
    ```
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2017.png)
    
3. Config
    
    ![Untitled](%5BTutorial%5D%20Kubernetes%E1%84%85%E1%85%B3%E1%86%AF%20%E1%84%90%E1%85%A9%E1%86%BC%E1%84%92%E1%85%A1%E1%86%AB%20MLOps%20%E1%84%89%E1%85%B5%E1%84%89%E1%85%B3%E1%84%90%E1%85%A6%E1%86%B7%20%E1%84%80%E1%85%AE%E1%84%8E%E1%85%AE%200cb15dc18dd1424b85af4356e315e2f1/Untitled%2018.png)
    

## **MLFlow 컴포넌트**