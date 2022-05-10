# 실습 코드 정리

### 3. CloudArchitectContainer-2022

```
# 20
sudo yum update -y
sudo yum install docker -y
sudo service docker start
sudo usermod -a -G docker ec2-user
exit

# 21
docker ps

# 22
docker run busybox echo "Hello world"

# 26
curl -O https://raw.githubusercontent.com/ddps-lab/architect-cloud/master/sample-application/flask-inference-docker/Dockerfile
cat Dockerfile

# 32
docker build -t flask-inference-image-for-ecs .

# 35
docker images

# 36
docker run --name flask-inference-container -p 80:80 -d flask-inference-image-for-ecs

# 37
docker ps
docker ps -a

# 40
docker inspect flask-inference-container

# 41
docker exec -it flask-inference-container bash

# 42
yum install procps -y
ps aux

# 43
ls /home/architect-cloud/sample-application/flask-inference
exit

# 44
docker stop flask-inference-container
docker ps -a

# 45
docker start flask-inference-container
docker ps

# 46
docker restart flask-inference-container
docker ps

# 47
docker stop flask-inference-container
docker rm flask-inference-container

# 54
aws configure

# 56
cat ~/.aws/credentials

# 57
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile

# 62
docker tag flask-inference-image-for-ecs $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/flask-inference-image-for-ecs

# 63
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com

# 64
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/flask-inference-image-for-ecs

# 67
rm -rf Dockerfile
curl -O https://raw.githubusercontent.com/ddps-lab/architect-cloud/master/sample-application/serverless-inference/Dockerfile
docker build -t flask-inference-image-for-lambda . --no-cache

# 68
docker tag flask-inference-image-for-lambda $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/flask-inference-image-for-lambda
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/flask-inference-image-for-lambda

# 73
https://samsung-cloud-architect-2022-05.s3.us-west-2.amazonaws.com/flask-inference-ecs-network-2022-05.yaml
```

### 4. CloudArchitectServerless-2022
```
# 75
https://raw.githubusercontent.com/ddps-lab/architect-cloud/master/sample-application/serverless-inference/index.html

# 119
'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Accept'
```
