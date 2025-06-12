#!/bin/bash

set -e

# 고정값
CLUSTER_NAME="coffee-supplier"
REGION="us-west-2"
VPC_NAME="LabVPC"

echo "🔍 Searching for VPC with Name tag: $VPC_NAME in region: $REGION..."

# VPC ID 자동 검색 (태그 Name이 LabVPC인 경우)
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[0].VpcId" \
  --output text)

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "❌ VPC named '$VPC_NAME' not found in region $REGION."
  exit 1
fi

echo "✅ Found VPC ID: $VPC_ID"

echo "Fetching subnets for VPC: $VPC_ID in region: $REGION..."

# 모든 서브넷 정보 가져오기
SUBNET_INFO=$(aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}" \
  --output json)

# 서브넷 정리
declare -A PUB_SUBNETS
declare -A PRIV_SUBNETS

for row in $(echo "${SUBNET_INFO}" | jq -c '.[]'); do
  SUBNET_ID=$(echo "$row" | jq -r '.ID')
  AZ=$(echo "$row" | jq -r '.AZ')
  IS_PUBLIC=$(echo "$row" | jq -r '.Public')

  if [[ "$IS_PUBLIC" == "true" ]]; then
    PUB_SUBNETS["$AZ"]=$SUBNET_ID
  else
    PRIV_SUBNETS["$AZ"]=$SUBNET_ID
  fi
done

# YAML 파일 생성
CONFIG_FILE="eks-${CLUSTER_NAME}.yaml"
cat > $CONFIG_FILE <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $CLUSTER_NAME
  region: $REGION

vpc:
  id: $VPC_ID
  subnets:
    private:
EOF

# 프라이빗 서브넷
for AZ in "${!PRIV_SUBNETS[@]}"; do
  echo "      $AZ:" >> $CONFIG_FILE
  echo "        id: ${PRIV_SUBNETS[$AZ]}" >> $CONFIG_FILE
done

echo "    public:" >> $CONFIG_FILE
# 퍼블릭 서브넷
for AZ in "${!PUB_SUBNETS[@]}"; do
  echo "      $AZ:" >> $CONFIG_FILE
  echo "        id: ${PUB_SUBNETS[$AZ]}" >> $CONFIG_FILE
done

cat >> $CONFIG_FILE <<EOF

nodeGroups:
  - name: ng-1
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 1
    maxSize: 3
    privateNetworking: true
    ssh:
      allow: true
EOF

echo "✅ YAML config generated: $CONFIG_FILE"

# eksctl 실행 여부 확인
read -p "▶️  Do you want to create the EKS cluster now using eksctl? (y/N): " yn
case $yn in
    [Yy]* ) eksctl create cluster -f $CONFIG_FILE;;
    * ) echo "EKS creation skipped. You can run: eksctl create cluster -f $CONFIG_FILE";;
esac