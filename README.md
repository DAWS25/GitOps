# GitOps

This is the GitOps repository for the DAWS25 organization.

Its purpose is to make sure our projects are delivered from the classroom to your device using repeatable, versioned infrastructure and deployment workflows.

## Why This Repo Exists

- Keep infrastructure and delivery definitions in Git as the source of truth.
- Make project environments reproducible across contributors and cohorts.
- Provide a practical environment to learn and practice modern platform engineering tools and ways of working.

## Platform Engineering Practice Environment

This repository is designed for hands-on practice with modern platform engineering and DevOps patterns, including:

- Git-driven infrastructure changes
- CloudFormation stack orchestration
- Environment promotion through reviewed commits
- Automated reconciliation between desired state and deployed state

The goal is not only to deploy systems, but to help learners build strong operational habits around reliability, traceability, and collaboration.

## How CloudFormation Git Sync Works

The `git-sync` directory contains stack descriptors and templates that define the desired AWS state.

### Key Components

- `git-sync/*.stack.yaml`: Stack descriptor files. These are the actionable deployment units used by the sync scripts. Each `.stack.yaml` points to one template and defines parameters/tags, effectively guiding creation and updates of a real CloudFormation stack.
- `git-sync/**/*.cform.yaml`: Raw CloudFormation templates that define resources. A `.cform.yaml` file by itself does nothing unless referenced by a `.stack.yaml`, so templates can be organized in different folders without deployment side effects.
- `git-sync/aws-deploy.sh`: Core reconciliation engine. It reads `.stack.yaml` files, resolves variables, checks hashes, and deploys only what changed.
- `git-sync/aws-gc.sh`: Cleanup and garbage-collection helper for stale or orphaned deployment artifacts/state created by previous runs.
- `git-sync/aws-apply.sh`: GC, then Deploy.

### Deployment Flow

1. Load environment variables (for tenant/env parameters and secret identifiers). Variables can be defined using any mechanism your system supports; we recommend [direnv](https://direnv.net/) for directory-scoped environment loading.
2. Read stack descriptor files in sequence.
3. Resolve template path, parameters, and tags.
4. Compute/compare template hashes to detect drift from desired Git state.
5. Call CloudFormation deploy/update for changed stacks.
6. Wait for completion and report status summary.

In short: Git declares desired state, and `aws-deploy.sh` reconciles AWS to match it.

Practical rule of thumb:

- Edit `.stack.yaml` when you want to control what gets deployed, with which parameters, and in which stack name context.
- Edit `.cform.yaml` when you want to change infrastructure resource definitions.

## Variables Used In `.stack.yaml` Files

The `.stack.yaml` descriptors define parameter values and tags passed to CloudFormation.

### Parameter Keys In Use

- `TenantId`: Primary tenant or project identifier used for naming and imports.
- `EnvId`: Environment identifier (for example `Main`, `Dev`, `Prod`).
- `VPCTenantId`: Tenant identifier used to import shared networking exports.
- `DomainName`: DNS name used by DNS/certificate-related stacks.
- `ParentHostedZoneId`: Route53 parent zone ID for delegation/alias stacks.
- `ManagedPolicyArn`: IAM managed policy ARN used by role templates.
- `GitHubToken`: GitHub token value/parameter used by source credential stacks.
- `InstanceName`: Name value for compute instance-related stacks.
- `ParamName`: SSM parameter name used by parameter writer stacks.
- `ParamValue`: SSM parameter value used by parameter writer stacks.
- `DBMasterUserSecretId`: Secrets Manager secret ID/ARN for DB credentials (username/password JSON).
- `KeycloakAdminSecretId`: Secrets Manager secret ID/ARN for Keycloak admin bootstrap credentials.

### Tag Keys In Use

- `TenantId`: Tenant ownership tag.
- `EnvId`: Environment tag.
- `ServiceId`: Service/application identifier tag.
- `KeyName`: Key pair or key identifier tag where relevant.

### Variable Source Notes

Values can be hardcoded in `.stack.yaml` files or supplied from environment variables using the interpolation supported by the deploy scripts.

You can define those environment variables using any mechanism your system supports; we recommend [direnv](https://direnv.net/) for directory-scoped configuration.

## Contributing

Contributions are welcome.

- Open an issue for bugs, gaps, or improvement ideas.
- Start a discussion for architecture proposals or learning topics.
- Submit a pull request for fixes and new capabilities.

If you are unsure where to start, open a ticket and we can help you pick a good first contribution.
