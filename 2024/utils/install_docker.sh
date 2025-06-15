#!/bin/bash

# ==========================================
# 시스템 초기 설정
# ==========================================
echo "시스템 패키지 업데이트 중..."
sudo apt-get update -y

# ==========================================
# 필수 패키지 설치
# ==========================================
echo "필수 패키지 설치 중..."
sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    -y

# ==========================================
# Docker 저장소 설정
# ==========================================
echo "Docker GPG 키 추가 중..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "Docker 저장소 추가 중..."
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# ==========================================
# Docker 설치
# ==========================================
echo "시스템 패키지 업데이트 중..."
sudo apt update -y

echo "Docker 설치 중..."
sudo apt install docker-ce -y

# ==========================================
# 사용자 권한 설정
# ==========================================
echo "Docker 그룹에 사용자 추가 중..."
sudo usermod -aG docker $USER
newgrp docker

echo "Docker 설치가 완료되었습니다!"


