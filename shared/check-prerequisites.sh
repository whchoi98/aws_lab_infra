#!/bin/bash
set -euo pipefail

# 모든 배포 단계에 필요한 도구를 점검하고, 없으면 자동 설치합니다.
# 각 배포 스크립트에서 source ./check-prerequisites.sh 로 호출합니다.
#
# 점검 대상: aws, eksctl, kubectl, helm, jq, python3

ARCH=$(uname -m)
echo "============================================"
echo "  배포 도구 점검 (Architecture: ${ARCH})"
echo "============================================"
echo ""

check_and_install() {
  local CMD=$1
  local NAME=$2
  local INSTALL_FN=$3

  if command -v "${CMD}" &>/dev/null; then
    local VER
    VER=$("${CMD}" version 2>/dev/null | head -1 || "${CMD}" --version 2>/dev/null | head -1 || echo "installed")
    echo "  ✅ ${NAME}: ${VER}"
  else
    echo "  ❌ ${NAME} 미설치 — 설치 중..."
    eval "${INSTALL_FN}"
    if command -v "${CMD}" &>/dev/null; then
      echo "  ✅ ${NAME} 설치 완료"
    else
      echo "  ❌ ${NAME} 설치 실패"
      return 1
    fi
  fi
}

install_awscli() {
  if [ "${ARCH}" = "aarch64" ]; then
    wget -q "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -O /tmp/awscliv2.zip
  else
    wget -q "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O /tmp/awscliv2.zip
  fi
  unzip -qo /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install --update && rm -rf /tmp/aws /tmp/awscliv2.zip
}

install_eksctl() {
  local EKSCTL_ARCH="amd64"
  [ "${ARCH}" = "aarch64" ] && EKSCTL_ARCH="arm64"
  curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${EKSCTL_ARCH}.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin/
}

install_kubectl() {
  local K8S_ARCH="amd64"
  [ "${ARCH}" = "aarch64" ] && K8S_ARCH="arm64"
  curl -sLO "https://dl.k8s.io/release/v1.33.0/bin/linux/${K8S_ARCH}/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
}

install_helm() {
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_jq() {
  sudo dnf install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo apt-get install -y jq 2>/dev/null
}

install_python3() {
  sudo dnf install -y python3 2>/dev/null || sudo yum install -y python3 2>/dev/null
}

# 점검 실행
check_and_install "aws"     "AWS CLI"  "install_awscli"
check_and_install "eksctl"  "eksctl"   "install_eksctl"
check_and_install "kubectl" "kubectl"  "install_kubectl"
check_and_install "helm"    "Helm"     "install_helm"
check_and_install "jq"      "jq"       "install_jq"
check_and_install "python3" "Python3"  "install_python3"

echo ""
echo "============================================"
echo "  ✅ 모든 도구 점검 완료"
echo "============================================"
