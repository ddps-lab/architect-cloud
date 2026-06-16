#!/bin/bash

# Set install path
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Add to PATH if not already present
if ! grep -q "$INSTALL_DIR" ~/.bashrc; then
  echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
fi

# install kubectl
echo "INSTALL kubectl for eks 1.33.0"
curl --silent --location -o "$INSTALL_DIR/kubectl" https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
chmod +x "$INSTALL_DIR/kubectl"
"$INSTALL_DIR/kubectl" version --client

# install eksctl
echo "INSTALL eksctl"
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv -v /tmp/eksctl "$INSTALL_DIR/eksctl"
chmod +x "$INSTALL_DIR/eksctl"
"$INSTALL_DIR/eksctl" version

# set $ACCOUNT_ID
echo 'export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)' >> ~/.bashrc
