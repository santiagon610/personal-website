#!/bin/sh
set -e

if [ -z "$S3_PERSONAL_SITE" ]; then
  echo "S3_PERSONAL_SITE environment var not set. Please set this variable and run again."
  exit 1
fi

aws sts get-caller-identity | jq
hugo
aws s3 sync ./public/ "s3://$S3_PERSONAL_SITE/"
rm -rf ./public/