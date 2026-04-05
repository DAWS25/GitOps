#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
pushd "$DIR/.."
echo "[$(date +'%Y-%m-%d %H:%M:%S')] script [$0] started dir[$DIR]"
##

echo "AWS tools" 
aws --version
sam --version
cdk --version

echo "Node.js"
node --version
npm --version

echo "Python"
python --version

echo "Java"
java -version

echo "Home"
pushd $HOME
find .
popd

echo "Git status"
git --version
git status

echo "whoami[$(whoami)] pwd[$(pwd)]"

echo "Sanity check completed."
##
popd
echo "[$(date +'%Y-%m-%d %H:%M:%S')] script [$0] completed"
