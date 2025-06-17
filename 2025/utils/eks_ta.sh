#!/bin/bash

set -e
CLUSTER_NAME="coffee-supplier"
REGION="us-west-2"

bash install_k8s.sh

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)

aws eks create-access-entry \
  --cluster-name coffee-supplier \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/OrganizationAccountAccessRole \
  --access-scope type=cluster \
  --permissions policyArn=arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy


# eksctl로 kubeconfig 설정
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION

# 클러스터 연결 확인
kubectl get nodes