#!/bin/bash

#install kubectl
echo "INSTALL kubectl for eks 1.33.0"
sudo curl --silent --location -o /usr/local/bin/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl
kubectl version

#install eksctl
echo "INSTALL eksctl"
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
eksctl version

#set $ACCOUNT_ID
echo 'export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)' >> ~/.bashrc