#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$DIR/.."
echo "script [$0] started"
#!
# for each git submodule module under modules/*, initialize git submodule if needed and update (pull latest changes) from origin main branch
for module_dir in modules/*/; do
    echo "Processing submodule: $module_dir"
    pushd "$module_dir"
    git fetch origin
    git checkout main
    git pull origin main
    if [ -f ".gitmodules" ]; then
        git submodule update --init --recursive
    fi
    popd
done
#!
popd
echo "script [$0] completed"
