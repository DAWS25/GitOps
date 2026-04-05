#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

"${DIR}/aws-deploy.sh"
"${DIR}/aws-gc.sh"
