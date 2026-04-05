#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"
REPO_ROOT="$(cd "${DIR}/../../../.." && pwd )"

echo "###################################"
echo "HELLO FROM THE PRESENCE WEBAPP HOOK"
echo "REPO_ROOT=${REPO_ROOT}"
echo "###################################"

# Verify that the module is initialized
MODULE_DIR="${REPO_ROOT}/modules/Presence"
# Iniialize git submodule or pull the module to main branch
if [ ! -d "${MODULE_DIR}/.git" ]; then
    echo "Initializing Presence module submodule..."
    git submodule update --init --recursive "${MODULE_DIR}"
else
    echo "Updating Presence module submodule..."
    pushd "${MODULE_DIR}"
    git fetch origin main
    git checkout main
    git pull origin main
    popd
fi

# Build the Presence module
pushd "${MODULE_DIR}"
echo "Building Presence module..."
make
popd

# Upload the webapp assets to S3
pushd "${MODULE_DIR}/presence_web/target"
echo "Uploading Presence web app..."
TENANT_ID="IncPerm"
ENV_ID="Presence"
BUCKET_STACK_NAME="IncPerm-Presence-Web-bucket-webapp"
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "${BUCKET_STACK_NAME}" --query "Stacks[0].Outputs[?OutputKey=='WebAppBucketName'].OutputValue" --output text)
aws s3 sync . "s3://${BUCKET_NAME}" --delete
popd

# Deploy SAM 
pushd "${MODULE_DIR}/presence_sam/"
echo "Deploying Presence SAM app..."
SAM_STACK_NAME="IncPerm-Presence-Web-sam"
sam deploy --template-file template.yaml \
    --stack-name "${SAM_STACK_NAME}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --resolve-s3 \
    --parameter-overrides \
        TenantId=IncPerm EnvId=Presence
popd

echo "PRESENCE WEBAPP HOOK COMPLETE"