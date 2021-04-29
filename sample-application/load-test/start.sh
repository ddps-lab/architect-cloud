#!/bin/bash
sudo yum -y update
sudo yum -y install gcc
sudo yum -y install python3-devel
sudo yum -y install git
sudo pip3 install locust

git clone https://github.com/kmu-bigdata/architect-cloud.git
#cd ./architect-cloud/sample-application/load-test
#locust -f locust-load-test.py

sudo cp loucst.service /etc/systemd/system/
sudo systemctl start locust
sudo systemctl enable locust
