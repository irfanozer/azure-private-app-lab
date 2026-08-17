# Evolving the lab into an enterprise layout

The single-repository layout makes the first lab runnable. The boundaries were
chosen so it can later become three independently versioned repositories.

## Target layout

```text
application-infrastructure repository
├── .github/workflows/infrastructure.yml   thin caller
└── infra/environments/dev/                 Terraform root module

platform-automation repository
├── .github/workflows/reusable-azure-terraform.yml
└── .github/actions/
    ├── azure-oidc-login/
    ├── terraform-check/
    ├── terraform-plan/
    └── terraform-apply/

terraform-azure-modules repository or private registry
├── network/
├── private-dns/
├── linux-web-vm/
├── storage/
└── private-endpoints/
```

## Change the caller reference

The application repository replaces its same-repository reference with an
immutable central reference:

```yaml
jobs:
  terraform:
    uses: your-org/platform-automation/.github/workflows/reusable-azure-terraform.yml@FULL_COMMIT_SHA
```

The application still owns its triggers, variables, state key, Environment
approvals, and maximum token permissions. The platform team owns job structure
and approved actions.

## Keep composite actions with the reusable workflow

On current GitHub Enterprise Cloud, the reusable workflow can retain:

```yaml
uses: $/.github/actions/terraform-plan
```

`$/` resolves to the repository containing the running reusable workflow at its
running commit. This atomically couples its actions to the workflow version.

GitHub Enterprise Server support differs. There, use an explicit reference:

```yaml
uses: your-org/platform-automation/.github/actions/terraform-plan@FULL_COMMIT_SHA
```

Do not assume `./.github/actions/...` refers to the platform repository. A
normal `actions/checkout` inside a cross-repository reusable workflow checks out
the caller/application repository.

## Move Terraform modules

Publish each module to a private Terraform registry, or reference a Git
repository at an immutable tag/SHA:

```hcl
module "network" {
  source  = "app.terraform.io/your-org/network/azurerm"
  version = "2.1.0"
}
```

The root module stays with the environment because it composes environment-
specific modules, state, and variables. Provider authentication remains in the
root; child modules declare provider requirements but not credentials.

Remember that `.terraform.lock.hcl` locks providers, not remote module
versions. Pin module versions explicitly.

## Enterprise controls to add

- Internal visibility for the platform repository
- Actions access policy for consuming repositories
- Full-SHA action and reusable-workflow references
- `CODEOWNERS` for workflows, actions, modules, and lock files
- Required platform-team approval
- Protected release tags
- Dependabot updates reviewed as pull requests
- Default read-only `GITHUB_TOKEN`
- Environment protection for write identities
- Separate state containers/keys and identities per environment
- Runner groups restricted to approved reusable workflows when private network
  access is required
- Audit-log monitoring for reusable workflow consumption

Example ownership file after replacing placeholder teams:

```text
/.github/workflows/  @your-org/platform-team
/.github/actions/    @your-org/platform-team
/infra/modules/      @your-org/cloud-platform-team
/.github/CODEOWNERS  @your-org/platform-admins
```

Protect the ownership file itself; otherwise a contributor could change the
reviewers before changing a privileged workflow.

## OIDC after splitting repositories

The standard OIDC subject still identifies the caller repository and
Environment:

```text
repo:your-org/application-repository:environment:development
```

The token also carries `job_workflow_ref`, which identifies the central reusable
workflow. This permits advanced enterprise policies that require deployments to
use an approved platform workflow, but provider/custom-claim support should be
verified before relying on it.

Official references:

- [Sharing actions and workflows with an enterprise](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/reuse-automations/share-with-your-enterprise)
- [Secure use of GitHub Actions](https://docs.github.com/en/actions/reference/security/secure-use)
- [OIDC with reusable workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows)
- [Terraform modules](https://developer.hashicorp.com/terraform/language/modules)
