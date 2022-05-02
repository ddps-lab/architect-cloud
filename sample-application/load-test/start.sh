#!/bin/bash
sudo yum -y update
sudo yum -y install gcc
sudo yum -y install python3-devel
sudo yum -y install git
sudo pip3 install locust==2.8.6
sudo pip3 install Flask==2.1.2
sudo pip3 install Jinja2==3.0.0

git clone https://github.com/ddps-lab/architect-cloud.git
cd ./architect-cloud/sample-application/load-test

sudo cp locust.service /etc/systemd/system/
sudo systemctl start locust
sudo systemctl enable locust
