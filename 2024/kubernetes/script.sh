eksctl create cluster --name hello-world \
  --nodes-min 3 \
  --nodes-max 6 \
  --managed \
  --alb-ingress-access \
  --asg-access \
  --region us-west-2 \
  --node-type t2.micro \
  --vpc-public-subnets=subnet-00b859213b23e1714,subnet-03dede645c3e46331 \
  --vpc-private-subnets=subnet-015d9580cc9b4ca2a,subnet-02172cec3d22b42fb


aws ec2 describe-subnets \
  --query "Subnets[?not_null(Tags[?Key=='Name'].Value | [0])].{ID:SubnetId, Name:Tags[?Key=='Name'].Value | [0]}" \
  --output table

aws ec2 create-tags \
    --tags "Key=karpenter.sh/nodepool,Value=default" \
    --resources $(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)


cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: inflate
          image: $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/customer
          resources:
            requests:
              cpu: 1
EOF


CLUSTER_NAME="mhsong-eks"
AWS_ACCOUNT_ID="694448341573"
REGION="ap-northeast-2"
KARPENTER_NODE_ROLE="mhsong-eks-karpenter-role"
KARPENTER_INTERRUPTION_QUEUE_ARN="arn:aws:sqs:ap-northeast-2:694448341573:mhsong-eks"

cat > controller-policy.json <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowScopedEC2InstanceAccessActions",
        "Effect": "Allow",
        "Resource": [
          "arn:aws:ec2:${REGION}::image/*",
          "arn:aws:ec2:${REGION}::snapshot/*",
          "arn:aws:ec2:${REGION}:*:security-group/*",
          "arn:aws:ec2:${REGION}:*:subnet/*"
        ],
        "Action": [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
      },
      {
        "Sid": "AllowScopedEC2LaunchTemplateAccessActions",
        "Effect": "Allow",
        "Resource": "arn:aws:ec2:${REGION}:*:launch-template/*",
        "Action": [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ],
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned"
          },
          "StringLike": {
            "aws:ResourceTag/karpenter.sh/nodepool": "*"
          }
        }
      },
      {
        "Sid": "AllowScopedEC2InstanceActionsWithTags",
        "Effect": "Allow",
        "Resource": [
          "arn:aws:ec2:${REGION}:*:fleet/*",
          "arn:aws:ec2:${REGION}:*:instance/*",
          "arn:aws:ec2:${REGION}:*:volume/*",
          "arn:aws:ec2:${REGION}:*:network-interface/*",
          "arn:aws:ec2:${REGION}:*:launch-template/*",
          "arn:aws:ec2:${REGION}:*:spot-instances-request/*"
        ],
        "Action": [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ],
        "Condition": {
          "StringEquals": {
            "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned"
          },
          "StringLike": {
            "aws:RequestTag/karpenter.sh/nodepool": "*"
          }
        }
      },
      {
        "Sid": "AllowScopedResourceCreationTagging",
        "Effect": "Allow",
        "Resource": [
          "arn:aws:ec2:${REGION}:*:fleet/*",
          "arn:aws:ec2:${REGION}:*:instance/*",
          "arn:aws:ec2:${REGION}:*:volume/*",
          "arn:aws:ec2:${REGION}:*:network-interface/*",
          "arn:aws:ec2:${REGION}:*:launch-template/*",
          "arn:aws:ec2:${REGION}:*:spot-instances-request/*"
        ],
        "Action": "ec2:CreateTags",
        "Condition": {
          "StringEquals": {
            "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
            "ec2:CreateAction": [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          },
          "StringLike": {
            "aws:RequestTag/karpenter.sh/nodepool": "*"
          }
        }
      },
      {
        "Sid": "AllowScopedResourceTagging",
        "Effect": "Allow",
        "Resource": "arn:aws:ec2:${REGION}:*:instance/*",
        "Action": "ec2:CreateTags",
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned"
          },
          "StringLike": {
            "aws:ResourceTag/karpenter.sh/nodepool": "*"
          },
          "ForAllValues:StringEquals": {
            "aws:TagKeys": [
              "karpenter.sh/nodeclaim",
              "Name"
            ]
          }
        }
      },
      {
        "Sid": "AllowScopedDeletion",
        "Effect": "Allow",
        "Resource": [
          "arn:aws:ec2:${REGION}:*:instance/*",
          "arn:aws:ec2:${REGION}:*:launch-template/*"
        ],
        "Action": [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ],
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned"
          },
          "StringLike": {
            "aws:ResourceTag/karpenter.sh/nodepool": "*"
          }
        }
      },
      {
        "Sid": "AllowRegionalReadActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ],
        "Condition": {
          "StringEquals": {
            "aws:RequestedRegion": "${REGION}"
          }
        }
      },
      {
        "Sid": "AllowSSMReadActions",
        "Effect": "Allow",
        "Resource": "arn:aws:ssm:${REGION}::parameter/aws/service/*",
        "Action": "ssm:GetParameter"
      },
      {
        "Sid": "AllowPricingReadActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": "pricing:GetProducts"
      },
      {
        "Sid": "AllowInterruptionQueueActions",
        "Effect": "Allow",
        "Resource": "${KARPENTER_INTERRUPTION_QUEUE_ARN}",
        "Action": [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
      },
      {
        "Sid": "AllowPassingInstanceRole",
        "Effect": "Allow",
        "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KARPENTER_NODE_ROLE}",
        "Action": "iam:PassRole",
        "Condition": {
          "StringEquals": {
            "iam:PassedToService": "ec2.amazonaws.com"
          }
        }
      },
      {
        "Sid": "AllowScopedInstanceProfileCreationActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": [
          "iam:CreateInstanceProfile"
        ],
        "Condition": {
          "StringEquals": {
            "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
            "aws:RequestTag/topology.kubernetes.io/region": "${REGION}"
          },
          "StringLike": {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
          }
        }
      },
      {
        "Sid": "AllowScopedInstanceProfileTagActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": [
          "iam:TagInstanceProfile"
        ],
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
            "aws:ResourceTag/topology.kubernetes.io/region": "${REGION}",
            "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
            "aws:RequestTag/topology.kubernetes.io/region": "${REGION}"
          },
          "StringLike": {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
          }
        }
      },
      {
        "Sid": "AllowScopedInstanceProfileActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ],
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
            "aws:ResourceTag/topology.kubernetes.io/region": "${REGION}"
          },
          "StringLike": {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
          }
        }
      },
      {
        "Sid": "AllowInstanceProfileReadActions",
        "Effect": "Allow",
        "Resource": "*",
        "Action": "iam:GetInstanceProfile"
      },
      {
        "Sid": "AllowAPIServerEndpointDiscovery",
        "Effect": "Allow",
        "Resource": "arn:aws:eks:${REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}",
        "Action": "eks:DescribeCluster"
      }
    ]
}
EOF
aws iam create-policy --policy-name KarpenterControllerPolicy-${CLUSTER_NAME} --policy-document file://controller-policy.json

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace karpenter \
  --role-name "${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
  --role-only \
  --approve


eksctl create iamserviceaccount \ --cluster "${CLUSTER_NAME}" --name karpenter --namespace karpenter \ --role-name "${CLUSTER_NAME}" \ --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \ --role-only \ --approve