# GitHub Token Setup for CodeBuild

## Step 1: Generate the Token

Run the script to generate your GitHub token:

```bash
./scripts/generate-github-token.sh
```

This will authenticate you with GitHub and display your token.

## Step 2: Add Token to CodeBuild

### Option A: Via AWS Console

1. Open the [AWS CodeBuild Console](https://console.aws.amazon.com/codesuite/codebuild/projects)
2. Select your build project: **presence-beta-deploy**
3. Click **Edit** → **Environment**
4. Scroll to **Additional configuration**
5. Under **Environment variables**, click **Add environment variable**
6. Enter:
   - **Name**: `GITHUB_TOKEN`
   - **Value**: (paste your token from Step 1)
   - **Type**: `Plaintext` (or `Secrets Manager` for better security)
7. Click **Update environment**

### Option B: Via AWS CLI

```bash
aws codebuild update-project \
  --name presence-beta-deploy \
  --environment '{
    "environmentVariables": [
      {
        "name": "GITHUB_TOKEN",
        "value": "your-token-here",
        "type": "PLAINTEXT"
      }
    ]
  }'
```

### Option C: Store in Secrets Manager (Recommended for Production)

1. Store the token in AWS Secrets Manager:
```bash
aws secretsmanager create-secret \
  --name github-token \
  --secret-string "your-token-here"
```

2. Update CodeBuild environment variable:
   - **Name**: `GITHUB_TOKEN`
   - **Value**: `github-token`
   - **Type**: `Secrets Manager`

## Step 3: Verify Configuration

The buildspec.yml already includes the pre_build phase that uses the token:

```yaml
pre_build:
  commands:
    - git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
    - git submodule update --init --recursive
```

## Important: CodeBuild Settings

Make sure **"Git submodules"** is **DISABLED** in your CodeBuild source configuration. The buildspec handles submodule initialization instead.

## Testing

Start a build and verify the pre_build phase successfully clones all submodules without SSH permission errors.
