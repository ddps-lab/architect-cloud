#!/bin/bash
sudo yum -y update
sudo yum -y install gcc
sudo yum -y install python3-devel
sudo yum -y install git
sudo pip3 install locust
sudo pip3 install Flask==1.1.2
sudo pip3 install Jinja2==2.11.3

git clone https://github.com/ddps-lab/architect-cloud.git
cd ./architect-cloud/sample-application/load-test

sudo cp locust.service /etc/systemd/system/
sudo systemctl start locust
sudo systemctl enable locust
