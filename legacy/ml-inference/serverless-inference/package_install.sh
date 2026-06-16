#!/bin/bash

# install python3.8
sudo yum -y groupinstall "Development Tools"
sudo yum -y install openssl-devel bzip2-devel libffi-devel
wget https://www.python.org/ftp/python/3.8.3/Python-3.8.3.tgz
tar xvf Python-3.8.3.tgz
cd Python-3.8*/
./configure --enable-optimizations
sudo make altinstall

# install Package Setting
sudo yum -y install gcc-c++
sudo yum -y install python3-devel

# install Packages
mkdir /home/ec2-user/mountpoint/efs/packages
pip3.8 install --upgrade pip --user
pip3.8 install --upgrade --target /home/ec2-user/mountpoint/efs/packages/ numpy
pip3.8 install --upgrade --target /home/ec2-user/mountpoint/efs/packages/ Pillow
pip3.8 install --upgrade --target /home/ec2-user/mountpoint/efs/packages/ requests-toolbelt
pip3.8 install --upgrade --target /home/ec2-user/mountpoint/efs/packages/ tensorflow
