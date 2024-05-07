#!/bin/bash

#install kubectl
echo "INSTALL kubectl"
sudo curl --silent --location -o /usr/local/bin/kubectl \
	   https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl
kubectl version

#install eksctl
echo "INSTALL eksctl"
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
eksctl version

#set $ACCOUNT_ID
echo 'export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)' >> ~/.bashrc