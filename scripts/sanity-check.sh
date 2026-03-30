#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
pushd "$DIR/.."
echo "[$(date +'%Y-%m-%d %H:%M:%S')] script [$0] started dir[$DIR]"
##
aws --version
cdk --version
pushd ..
find .
popd
echo "Sanity check completed"
##
popd
echo "[$(date +'%Y-%m-%d %H:%M:%S')] script [$0] completed"
