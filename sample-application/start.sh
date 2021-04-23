#!/bin/bash
sudo yum update -y
sudo yum install git -y
sudo yum install python3-pip -y
pip3 install virtualenv

cd /home/ec2-user/
git clone https://github.com/unhochoi/flask-web-application-in-ec2.git
cd flask-web-application-in-ec2
mkdir -p static/uploads

virtualenv venv
. venv/bin/activate
sudo -H pip3 install --upgrade --ignore-installed pip setuptools
pip3 install -r requirements.txt

sudo cp main.service /etc/systemd/system/
sudo systemctl start main
sudo systemctl enable main
