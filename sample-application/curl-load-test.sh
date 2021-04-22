#!/bin/bash

TEST_URL=$1
TEST_FILE=$2
TEST_NUM=$3

for ((i=1; i<=$TEST_NUM; i++))
do
    curl -X POST -F "file=@$TEST_FILE" $TEST_URL
done