#! /usr/bin/env bash
set -e

ssh-keyscan -H shardbox.org 2>&1 | tee -a ${TRAVIS_HOME}/.ssh/known_hosts

echo -e "$SSH_PRIVATE_KEY" > private_ssh_key
chmod 0700 private_ssh_key

docker images

docker save $DEPLOY_IMAGE:b$TRAVIS_BUILD_NUMBER | \
  ssh -i private_ssh_key deploy@shardbox.org \
    "docker load | dokku tags:deploy shardbox b$TRAVIS_BUILD_NUMBER"
