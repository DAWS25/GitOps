#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

aws sts get-caller-identity
sleep 10
echo "Starting GC..."
"${DIR}/aws-gc.sh"
echo "GC complete, proceeding to deploy..."
sleep 10
"${DIR}/aws-deploy.sh"
echo "Done"