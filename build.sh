#!/bin/bash

docker run \
    --rm \
    --privileged \
    -v ~/.docker:/root/.docker \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -v $(pwd):/data \
    homeassistant/aarch64-builder \
    --all \
    --target dropback