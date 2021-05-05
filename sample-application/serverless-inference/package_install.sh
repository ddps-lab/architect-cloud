#!/bin/bash

# install python3.8
sudo yum -y groupinstall "Development Tools"
sudo yum -y install openssl-devel bzip2-devel libffi-devel
sudo wget https://www.python.org/ftp/python/3.8.3/Python-3.8.3.tgz
sudo tar xvf Python-3.8.3.tgz
sudo cd Python-3.8*/
sudo ./configure --enable-optimizations
sudo make altinstall

# install Package Setting
sudo yum -y install gcc-c++
sudo yum -y install python3-devel

# install Packages
pip3.8 install --upgrade --target efs/packages/ numpy
pip3.8 install --upgrade --target efs/packages/ Pillow
pip3.8 install --upgrade --target efs/packages/ requests-toolbelt
pip3.8 install --upgrade --target efs/packages/ tensorflow
