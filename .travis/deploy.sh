#! /usr/bin/env bash
set -e
echo "$SSH_PRIVATE_KEY" | tr -d '\r' > private_ssh_key

docker save $DEPLOY_IMAGE:b$TRAVIS_BUILD_NUMBER | ssh -i private_ssh_key dokku@shardbox.org "docker load | dokku tags:deploy shardbox b$TRAVIS_BUILD"
