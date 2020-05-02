#! /usr/bin/env bash
set -e
echo -e "$SSH_PRIVATE_KEY" > private_ssh_key
chmod 0700 private_ssh_key

GIT_SSH_COMMAND='ssh -i private_ssh_key' git push ssh://dokku@shardbox.org/shardbox master
