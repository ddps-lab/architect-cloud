#!/bin/bash
sudo yum update -y
sudo yum install git -y
sudo yum install python3-pip -y
sudo pip3 install virtualenv

cd /home/ec2-user/
git clone https://github.com/ddps-lab/architect-cloud.git
cd architect-cloud/sample-application/flask-inference/
mkdir -p static/uploads

virtualenv venv
. venv/bin/activate
pip3 install -r requirements.txt

sudo cp main.service /etc/systemd/system/
sudo systemctl start main
sudo systemctl enable main
