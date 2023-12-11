#!/bin/sh
set -e

DEPLOY_TARGET=${1:-production}

aws sts get-caller-identity | jq
hugo
hugo deploy --target="${DEPLOY_TARGET}"
rm -rf ./public/
