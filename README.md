# architect-cloud

If your Google Cloud Console is once disconnected, run the command below on Google Cloud Console before you start typing anything.

```sh
$ export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
```


Set variable for EKS

```sh
rm -vf ${HOME}/.aws/credentials

sudo yum install jq -y

export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

```
