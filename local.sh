#!/usr/bin/env bash

set -ex

podman build -t personal-website:latest .
podman run -it --rm -p 8080:8080 personal-website:latest