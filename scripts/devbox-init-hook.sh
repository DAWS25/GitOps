#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!
aws --version
cdk --version
#!
popd
echo "script [$0] completed"
