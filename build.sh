#!/bin/bash

docker run \
    --rm \
    --privileged \
    -v "$(pwd)":/data \
    homeassistant/aarch64-builder \
    --all \
    --target dropback \
    --docker-user $DOCKER_USER \
    --docker-password $DOCKER_PASSWORD
