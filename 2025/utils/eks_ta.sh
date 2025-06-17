#!/bin/bash

set -e
CLUSTER_NAME="coffee-supplier"
REGION="us-west-2"

bash install_k8s.sh

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)

aws eks create-access-entry \
  --cluster-name coffee-supplier \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --type STANDARD \
  --username ta-user

aws eks associate-access-policy \
  --cluster-name coffee-supplier \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=cluster

# eksctl로 kubeconfig 설정
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION

# 클러스터 연결 확인
kubectl get nodes