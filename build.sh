#!/bin/bash

docker run \
    --rm \
    --privileged \
    -v "$(pwd)":/data \
    homeassistant/aarch64-builder \
    --all \
    --target $(find . -type f -name "Dockerfile" -exec dirname {} \; | awk -F'/' '{print $NF}') \
    --docker-user $DOCKER_USER \
    --docker-password $DOCKER_PASSWORD
