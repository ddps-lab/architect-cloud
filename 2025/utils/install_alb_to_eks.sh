#!/bin/bash
set -e

# 변수 설정
CLUSTER_NAME="coffee-supplier"
REGION="us-west-2"
VPC_NAME="LabVPC"

echo "🔧 Helm 설치 중..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
echo "✅ Helm 설치 완료"

echo "📄 AWS Load Balancer Controller용 IAM 정책 다운로드 중..."
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.0/docs/install/iam_policy.json
echo "✅ ALB IAM 정책 다운로드 완료"


echo "🛡️ ALB IAM 정책 생성 중..."
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
echo "✅ ALB IAM 정책 생성 완료"

echo "👤 ALB IAM Service Account 생성 중..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

eksctl utils associate-iam-oidc-provider \
    --region "$REGION" \
    --cluster "$CLUSTER_NAME" \
    --approve

eksctl create iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::"$ACCOUNT_ID":policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --region "$REGION" \
    --approve
echo "✅ ALB IAM Service Account 생성 완료"

echo "📦 Helm Chart 저장소 추가 중..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update
echo "✅ Helm 저장소 업데이트 완료"

echo "🚀 AWS Load Balancer Controller 설치 중..."
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
echo "✅ ALB Controller 설치 완료"

echo "🔍 설치된 컨트롤러 확인 중..."
kubectl get deployment -n kube-system aws-load-balancer-controller
