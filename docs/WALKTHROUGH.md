# Why every step exists

This document follows one run from initial bootstrap to Azure resources. The
main design principle is to give each layer one responsibility.

## 1. Bootstrap the trust and state layer

The bootstrap script is run once by a human with elevated Azure permissions.
This is the unavoidable trust bootstrap: GitHub cannot use OIDC until an Azure
identity already exists and trusts GitHub.

### Bootstrap resource group

It contains the long-lived deployment identities and Terraform backend. It is
separate from the lab resource group so a Terraform destroy cannot delete its
own identity or state halfway through execution.

### Azure Blob backend

Local state is unsafe for a shared pipeline. Azure Blob provides centralized
state, locking through blob leases, and consistency checking. The state account
is reachable from GitHub-hosted runners but:

- Blob public access is disabled.
- Shared-key access is disabled after the one-time container bootstrap.
- Authentication uses Entra ID and OIDC.
- Each GitHub identity is scoped to only the state container.

The backend needs `Storage Blob Data Contributor`, not ordinary Azure
`Contributor`, because state operations use the Blob data plane. It also needs
write operations for its lease/lock, even when Terraform is producing a plan.
[HashiCorp documents these backend permissions](https://developer.hashicorp.com/terraform/language/backend/azurerm#storage-account-required-role-assignments).

### Two GitHub deployment identities

| Identity | Lab resource group | State container | Purpose |
|---|---|---|---|
| Plan UAMI | Reader | Blob Data Contributor | Refresh state and calculate changes |
| Apply UAMI | Contributor + RBAC Administrator | Blob Data Contributor | Create/delete resources and assign workload roles |

`Contributor` cannot create role assignments. This example creates Blob roles
for App Service identities, so the apply identity additionally receives **Role
Based Access Control Administrator** at the lab resource-group scope—not the
whole subscription.

### Federated identity credentials

The two Azure identities trust these GitHub OIDC subjects:

```text
repo:OWNER/REPOSITORY:environment:terraform-plan
repo:OWNER/REPOSITORY:environment:development
```

Both use:

```text
issuer   = https://token.actions.githubusercontent.com
audience = api://AzureADTokenExchange
```

GitHub gets a short-lived signed token. Entra validates issuer, audience, and
subject, then issues an Azure access token for the matching managed identity.
There is no stored password to rotate. `id-token: write` only allows requesting
the GitHub token; Azure RBAC decides what the resulting identity can do.

## 2. Configure GitHub's control layer

The GitHub configuration script creates two Environments:

- `terraform-plan` selects the read-oriented Azure identity.
- `development` selects the write identity and should require approval.

Environment protection happens before the apply job begins. Therefore the
write-capable job cannot obtain its OIDC token until the reviewer approves it.

Tenant IDs, subscription IDs, client IDs, resource-group names, and Storage
account names are identifiers rather than passwords. They are repository
variables. There is no `AZURE_CLIENT_SECRET`.

## 3. The thin caller workflow

[`infrastructure.yml`](../.github/workflows/infrastructure.yml) owns only the
repository-specific concerns:

- Triggers and path filters
- Plan versus apply choice
- Terraform directory/version
- Environment and state names
- The maximum `GITHUB_TOKEN` permissions
- Concurrency for this state

The key line is job-level `uses`:

```yaml
jobs:
  terraform:
    uses: $/.github/workflows/reusable-azure-terraform.yml
```

Job-level `uses` calls a reusable workflow. Because it is not a normal runner
job, the caller does not contain `runs-on` or `steps`.

The concurrency group covers plan, approval, and apply. A second run cannot
change state while someone is reviewing the first run's plan, and
`cancel-in-progress: false` avoids terminating Terraform in the middle of an
apply.

## 4. The reusable workflow

[`reusable-azure-terraform.yml`](../.github/workflows/reusable-azure-terraform.yml)
is the centrally maintainable policy and orchestration layer.

### Validate job

This job receives no Azure identity. It checks formatting, downloads the locked
providers, initializes with `-backend=false`, and validates the Terraform
configuration. Syntax errors should not require cloud credentials.

### Plan job

The plan job:

1. Rejects cloud access for untrusted fork pull requests.
2. Targets the `terraform-plan` Environment, which determines its OIDC subject.
3. Grants only `contents: read` and `id-token: write` to `GITHUB_TOKEN`.
4. Uses the internal OIDC action, which calls Microsoft's `azure/login` action.
5. Calls the internal plan action with parameters.
6. Archives the initialized workspace and saved plan for one day.

Terraform plan files can contain sensitive values. They should not be published
or retained indefinitely.

### Apply job

The apply job exists only for `apply` or `destroy`. It:

1. Waits for the plan job.
2. Waits for the protected `development` Environment.
3. Obtains the separate write identity through OIDC.
4. Downloads the artifact from the same workflow run.
5. Applies the exact saved `tfplan` rather than creating a new plan.

This creates a meaningful review boundary: the approved plan and applied plan
are the same file with the same initialized providers and modules.

## 5. Internal composite actions

The reusable workflow controls jobs. Composite actions package repeatable
steps inside those jobs.

| Composite action | Repeated responsibility |
|---|---|
| `azure-oidc-login` | Standard company OIDC login and session check |
| `terraform-check` | Install, format check, backend-free init, validate |
| `terraform-plan` | Backend init and normal/destroy saved plan |
| `terraform-apply` | Install exact CLI and apply saved plan |

They receive values through `with:` parameters. Shell values are first placed
in environment variables and quoted, rather than interpolating an expression
directly into a command.

These are internally authored composite actions, but they call vendor actions:

- `azure/login`
- `hashicorp/setup-terraform`
- `actions/checkout`
- `actions/upload-artifact` and `actions/download-artifact`

Vendor versus internal is an ownership/trust classification. It is not a
GitHub action implementation type.

## 6. Terraform root and child modules

[`infra/environments/dev`](../infra/environments/dev) is the **root module**.
It chooses environment-specific values and composes child modules.

```text
root module
├── network module
├── private DNS module
├── storage module
├── App Service Plan module
├── web-app module (reader instance)
├── web-app module (writer instance)
├── private-endpoints module
└── private-DNS-resolver module (optional)
```

The web-app child module is instantiated twice with different parameters. Each
call has its own Terraform resource address and Azure managed identity.

Terraform does not execute modules top to bottom. References such as
`module.storage.id` and `module.network.private_endpoint_subnet_id` form one
dependency graph. Independent resources may be created concurrently.

## 7. VNet and subnet separation

The lab uses `10.42.0.0/16` with these subnets:

| Subnet | Prefix | Why separate? |
|---|---|---|
| App integration | `10.42.0.0/26` | Delegated to `Microsoft.Web/serverFarms`; App Service outbound path |
| Private Endpoints | `10.42.1.0/27` | Contains inbound Private Endpoint NICs |
| Resolver inbound | `10.42.3.0/28` | Optional, dedicated `Microsoft.Network/dnsResolvers` subnet |
| Resolver outbound | `10.42.3.16/28` | Optional, separate resolver delegation |

App Service Private Endpoint and VNet integration solve opposite directions:

```text
Client → Private Endpoint → Web App       inbound
Web App → VNet integration → Storage PE  outbound
```

They cannot share a subnet. [Microsoft's App Service networking documentation](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
explains the outbound integration model.

## 8. App Service as the Elastic Beanstalk analogue

The B1 Linux App Service Plan is the managed compute pool. Both web apps run in
the same plan, just as several apps can share App Service Plan capacity.

Each web app:

- Runs a public Nginx image so no private SCM deployment path is initially
  required.
- Disables public inbound access.
- Disables FTP and WebDeploy basic authentication.
- Requires HTTPS/TLS 1.2.
- Uses a system-assigned managed identity.
- Uses the delegated subnet for outbound VNet integration.
- Receives its own Private Endpoint for inbound traffic.

The Private Endpoint is not a deployment mechanism. A future source deployment
to private SCM/Kudu needs a VNet-connected runner or another deliberately
secured path. OIDC solves authentication, not network reachability.

## 9. Managed identities and least-privilege RBAC

The reader and writer apps have different system-assigned identities:

- Reader: `Storage Blob Data Reader`
- Writer: `Storage Blob Data Contributor`

The assignment is scoped to one Storage account. Azure `Reader`, `Contributor`,
and `Storage Account Contributor` are control-plane roles and do not grant Blob
data access.

The baseline Nginx image does not call Storage; it keeps the first lab focused
on infrastructure, identity issuance, and RBAC configuration. Exercising both
data roles from application code or a VNet-connected test container is a
natural follow-up lab.

There is no practical built-in Blob “write-only” role. Writing commonly needs
read/list/ETag operations; Blob Data Contributor includes read, write, and
delete. A custom write-only role can be constructed, but it is frequently
unusable and would require extra privilege to create. Separate workload
identities and the narrowest resource scope are the more useful lesson.

The system-assigned identity's **principal ID** is used in role assignments.
A client ID is used when software explicitly selects a user-assigned identity.

## 10. Private Endpoint and Private DNS

Three Private Endpoints bring these service interfaces into the VNet:

- Storage Blob: subresource `blob`
- Reader App Service: subresource `sites`
- Writer App Service: subresource `sites`

Matching zones are:

```text
privatelink.blob.core.windows.net
privatelink.azurewebsites.net
```

Each zone is linked to the VNet. Each endpoint has a
`private_dns_zone_group`, so Azure manages the required A records. For App
Service this includes the SCM/Kudu record.

Clients still use the normal service hostname. Public DNS returns a CNAME into
the `privatelink` namespace; a client using the linked VNet's DNS receives the
private A record. [Microsoft publishes the authoritative service-to-zone table](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns).

The Storage module intentionally does not create a container or blob. Those are
data-plane operations and a public GitHub-hosted runner cannot reach the
private-only Blob endpoint. A VNet-connected workload can create data later.

## 11. DNS Private Resolver

Linked Private DNS zones already answer queries for this VNet. DNS Private
Resolver is for hybrid or centralized DNS:

- **Inbound endpoint:** on-premises/other-network DNS forwards Azure-private
  queries to its private IP.
- **Outbound endpoint and ruleset:** Azure conditionally forwards a suffix such
  as `corp.example.com.` to custom/on-premises DNS servers.
- **VNet link:** makes a forwarding ruleset available to a VNet.

The module creates both endpoint types and an empty forwarding ruleset when
enabled. Add a real forwarding rule only when you have a reachable DNS target;
a fake target proves resource creation but not DNS behavior.

Resolver endpoint subnets must be dedicated, delegated, and between /28 and
/24. The resolver and VNet must be in the same region. See [Azure DNS Private
Resolver constraints](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview).

## 12. What verification proves

The included verification script proves management-plane configuration:

- Resources exist.
- Private Endpoint connections are approved.
- Private DNS zones and records exist.
- Public network access is disabled.
- Managed identities have principal IDs.

It cannot prove the data path from a public workstation. A complete private
test requires a VNet-connected VM, container, runner, or hybrid network. That is
a good next hands-on extension rather than leaving another continuously billed
test resource in the baseline.

## AWS mental mapping

| This lab | Approximate AWS concept |
|---|---|
| VNet/subnet | VPC/subnet |
| App Service | Elastic Beanstalk managed application platform |
| Private Endpoint | Interface VPC endpoint/PrivateLink endpoint |
| Private DNS zone link | Route 53 private hosted zone association |
| DNS Private Resolver | Route 53 Resolver inbound/outbound endpoints |
| User-assigned managed identity | Reusable IAM role-like workload identity |
| System-assigned managed identity | Instance/task role tied to one resource lifecycle |
| Federated credential | IAM role trust policy for an OIDC principal |
| Azure role assignment | IAM policy attachment, with Azure scope hierarchy |
| GitHub plan/apply identity | Separate read and deploy IAM roles |
