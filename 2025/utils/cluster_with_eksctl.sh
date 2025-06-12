#!/bin/bash

set -e

# 고정값
CLUSTER_NAME="coffee-supplier"
REGION="us-west-2"
K8S_VERSION="1.33"

# 사용자로부터 VPC ID 입력받음
VPC_ID=$1
if [[ -z "$VPC_ID" ]]; then
  echo "Usage: $0 <vpc-id>"
  exit 1
fi

echo "📦 Fetching subnets for VPC: $VPC_ID in region: $REGION..."

# 모든 서브넷 정보 가져오기
SUBNET_INFO=$(aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}" \
  --output json)

# 서브넷 분류
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
  version: "$K8S_VERSION"

vpc:
  id: $VPC_ID
  subnets:
    private:
EOF

for AZ in "${!PRIV_SUBNETS[@]}"; do
  echo "      $AZ:" >> $CONFIG_FILE
  echo "        id: ${PRIV_SUBNETS[$AZ]}" >> $CONFIG_FILE
done

echo "    public:" >> $CONFIG_FILE
for AZ in "${!PUB_SUBNETS[@]}"; do
  echo "      $AZ:" >> $CONFIG_FILE
  echo "        id: ${PUB_SUBNETS[$AZ]}" >> $CONFIG_FILE
done

cat >> $CONFIG_FILE <<EOF

nodeGroups:
  - name: coffee-supplier-node-group
    instanceType: t3.small
    desiredCapacity: 3
    minSize: 3
    maxSize: 6
    privateNetworking: false
    ssh:
      allow: true
EOF

echo "YAML config generated: $CONFIG_FILE"

eksctl create cluster -f $CONFIG_FILE