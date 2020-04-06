#! /usr/bin/env bash
set -e

make bin/app
export DATABASE_URL=$TEST_DATABASE_URL
bin/app &
sleep 1
curl http://localhost:3000/ -v > /dev/null
