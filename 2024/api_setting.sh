#!/bin/bash

customer_directory="/home/cloudshell-user/architect-cloud/2024/s3_customer"
employee_directory="/home/cloudshell-user/architect-cloud/2024/s3_employee"

echo "Enter the API URL of customer: "
read customer_api

cd "$customer_directory"

for file in *.html; do
    sed -i "s|YOUR_API_URL|$customer_api|g" "$file"
done

echo "Enter the API URL of employee: "
read employee_api

cd "$employee_directory"

for file in *.html; do
    sed -i "s|YOUR_API_URL|$employee_api|g" "$file"
done