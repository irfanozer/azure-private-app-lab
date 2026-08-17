# Why every step exists

This document follows one run from bootstrap to a browser-visible Azure VM.
Each layer has one responsibility: GitHub orchestrates, Entra authenticates,
Azure RBAC authorizes, Terraform declares resources, and Azure networking moves
traffic.

## 1. Bootstrap the trust and state layer

Bootstrap runs once as a human with elevated Azure permissions. GitHub cannot
use OIDC until an Azure identity already exists and trusts GitHub, so this small
first step cannot be performed by the new pipeline itself.

The bootstrap resource group contains:

- An Azure Storage account and Blob container for Terraform state
- A plan user-assigned managed identity
- An apply user-assigned managed identity
- One GitHub federated credential on each identity
- The Azure role assignments needed by those identities

It is separate from the lab resource group. Terraform can therefore destroy
the workload without deleting its own state or deployment identity midway.

### Why the backend uses Blob Data Contributor

Terraform state operations use the Blob **data plane**. Even plan must read and
refresh state and acquire a Blob lease for locking, so both deployment
identities need `Storage Blob Data Contributor` on the state container.
Ordinary Azure `Contributor` is a management-plane role and is not enough for
Blob data.

The state account accepts Entra authentication, has shared-key access disabled,
and contains no GitHub client secret.

### Why there are two deployment identities

| Identity | Lab resource group | State container | Purpose |
|---|---|---|---|
| Plan UAMI | Reader | Blob Data Contributor | Inspect Azure and calculate changes |
| Apply UAMI | Contributor + RBAC Administrator | Blob Data Contributor | Change resources and assign the VM role |

`Contributor` cannot create role assignments. The apply identity therefore
also has `Role Based Access Control Administrator`, scoped only to the lab
resource group.

These are deployment identities for GitHub. They are different from the VM's
system-assigned workload identity.

### Federated identity credentials

The identities trust these exact GitHub OIDC subjects:

```text
repo:OWNER/REPOSITORY:environment:terraform-plan
repo:OWNER/REPOSITORY:environment:development
```

GitHub creates a short-lived signed OIDC token. Microsoft Entra checks its
issuer, audience, and subject and exchanges it for an Azure access token for
the matching identity. Azure RBAC then determines what that identity can do.

## 2. Configure GitHub's control layer

`configure-github.ps1` creates two GitHub Environments:

- `terraform-plan` selects the read-oriented Azure identity.
- `development` selects the write identity and should require approval.

It also creates repository variables containing tenant ID, subscription ID,
client IDs, resource-group name, and state settings. These are identifiers, not
passwords. There is no `AZURE_CLIENT_SECRET`.

The repository already exists; a GitHub **Environment** is a deployment-policy
object inside that repository. It can enforce approval, branch restrictions,
wait timers, and environment-scoped values.

## 3. Workflow execution order

```text
push or Run workflow
→ thin caller workflow
→ reusable workflow
→ validate job
→ plan job using plan OIDC identity
→ save exact plan artifact
→ wait for development approval
→ apply job using apply OIDC identity
→ apply the saved plan
→ cloud-init installs Nginx on the VM
```

The caller owns the trigger and repository-specific inputs. Its job-level
`uses` calls the reusable workflow. The reusable workflow owns jobs, runners,
environments, authentication, and ordering. Composite actions are invoked at
step level to package repeated operations such as Terraform validation or
planning.

### Validate job

Validation receives no Azure identity. It checks formatting, initializes
without the remote backend, and validates the configuration.

### Plan job

Plan enters the `terraform-plan` Environment, requests a GitHub OIDC token,
logs in as the plan UAMI, reads remote state, refreshes existing Azure objects,
and calculates a saved plan. It does not make the planned Azure changes.

### Apply job

Apply runs only after the protected `development` Environment is approved. It
logs in as the separate apply UAMI and applies the exact saved `tfplan`; it does
not generate a different plan after approval.

## 4. Terraform root and child modules

`infra/environments/dev` is the root module:

```text
root module
├── network
├── linux-web-vm
├── storage
├── private-dns
├── private-endpoints
└── private-dns-resolver (optional)
```

The root chooses names and environment values. Child modules implement reusable
components. Providers are separate plugins that translate Terraform operations
into Azure API calls.

Terraform follows references to build a dependency graph. Independent objects
may be created in parallel; file order does not define execution order.

## 5. VM networking

The VNet address space is `10.42.0.0/16`:

| Subnet | Prefix | Purpose |
|---|---|---|
| Compute | `10.42.0.0/26` | Contains the VM network interface |
| Private Endpoints | `10.42.1.0/27` | Contains the private IP mapped to Storage Blob |
| Resolver inbound | `10.42.3.0/28` | Optional DNS queries entering Azure |
| Resolver outbound | `10.42.3.16/28` | Optional DNS forwarding leaving Azure |

The VM is IaaS: its NIC really is attached to the compute subnet. This differs
from multitenant App Service, where VNet integration merely gives an outbound
path to workers hosted outside the VNet.

### Browser traffic

```text
Browser
→ static Public IP
→ VM network interface
→ NSG allows TCP 80
→ Nginx on the VM
```

The NSG explicitly allows HTTP 80 from the Internet and denies SSH 22. Azure's
default rules deny other unsolicited Internet traffic. The public IP is also
the VM's explicit outbound path for downloading Ubuntu packages during
cloud-init.

### Storage traffic

```text
VM application
→ asks DNS for STORAGE.blob.core.windows.net
→ linked Private DNS zone returns the Blob Private Endpoint IP
→ VM routes inside the VNet to snet-private-endpoints
→ Private Link maps that IP to this exact Storage account's blob subresource
→ Storage validates the VM's Entra token and Blob data role
```

Three checks are independent:

1. DNS must return the intended private IP.
2. Routing and network rules must allow the connection.
3. Identity and RBAC must authorize the requested Blob operation.

OIDC and RBAC do not create network reachability, and successful networking
does not grant authorization.

## 6. VM, Nginx, and cloud-init

Terraform creates:

- A Standard static Public IPv4 address
- A Network Security Group
- A network interface in `snet-compute`
- An Ubuntu Server 24.04 LTS Gen2 VM using `Standard_F1als_v7`
- A Standard LRS managed OS disk
- A system-assigned managed identity

`Standard_F1als_v7` uses an NVMe disk controller. Trusted Launch features
enable Secure Boot and virtual TPM. Cloud-init installs Nginx and replaces its
default page with the lab success page.

Terraform must supply an administrator credential to Azure. This disposable
lab generates a strong password into protected Terraform state, does not output
it, exposes no SSH rule, and locks the local administrator password after
cloud-init. Use Azure Run Command for diagnostics. In production, prefer a
managed access solution and an approved SSH/Entra policy.

Terraform can report VM creation before cloud-init finishes. Wait two to five
minutes before treating the first HTTP failure as a network problem.

## 7. Managed identity and workload RBAC

When Azure creates the VM, it also creates a system-assigned identity tied to
that VM's lifecycle. Terraform reads its principal/object ID and creates:

```text
principal: VM system-assigned identity
role:      Storage Blob Data Contributor
scope:     this one application Storage account
```

That role permits Blob read, write, and delete data operations. It does not make
the VM a Contributor on the resource group or subscription.

The public Nginx page is deliberately static, so HTTP verification proves the
VM and inbound network path, not Blob authorization. A follow-up exercise can
use Azure Run Command from the VM to obtain a managed-identity token and access
Blob through the private endpoint.

## 8. Private Endpoint and Private DNS

A Private Endpoint is a NIC-like private IP in `snet-private-endpoints` mapped
to one Azure PaaS resource and subresource. In this lab it maps only to the
Storage account's `blob` subresource. It does not move the Storage service into
the VNet.

The private DNS zone is:

```text
privatelink.blob.core.windows.net
```

It is linked to the VNet. The endpoint's DNS zone group lets Azure manage the A
record. Workloads continue using the normal Storage hostname; DNS follows its
CNAME into the `privatelink` zone and returns the private address.

The Storage account's public network access is disabled explicitly. A Private
Endpoint alone does not universally disable a service's public endpoint.

## 9. DNS Private Resolver

Private DNS Resolver is disabled by default because a zone linked directly to
this single VNet already resolves correctly.

- The **inbound endpoint** lets on-premises or another connected network forward
  Azure-private DNS questions to Azure.
- The **outbound endpoint plus ruleset** lets Azure forward selected suffixes to
  reachable custom or on-premises DNS servers.

Resolver moves DNS questions only. It does not create the VPN, ExpressRoute,
peering, route, or application connection needed after a name resolves.

## 10. What verification proves

`verify-azure.ps1` shows:

- Bootstrap state and OIDC identities
- Terraform-created resources
- Private Endpoint approval and Private DNS zone
- VM power state, public/private IPs, and managed identity
- The HTTP NSG rule and absence of an SSH allow rule
- The VM's Blob data role assignment
- The browser URL and an HTTP status test

If HTTP fails, troubleshoot in this order: VM running state, cloud-init/Nginx,
Public IP, NSG rule, then guest firewall. For private Storage, troubleshoot DNS,
route, endpoint approval, then identity/RBAC.

## AWS mental mapping

| Azure lab concept | Approximate AWS concept |
|---|---|
| VNet/subnet | VPC/subnet |
| Linux VM | EC2 instance |
| VM system-assigned managed identity | EC2 instance profile/role |
| User-assigned deployment identity | Reusable IAM role-like identity |
| Federated credential | IAM role trust policy for GitHub OIDC |
| Azure role assignment | IAM policy attachment plus a resource scope |
| NSG | Security Group, with explicit deny/NACL-like features |
| Standard Public IP | Elastic IP |
| Blob Private Endpoint | Interface VPC endpoint/PrivateLink endpoint |
| Private DNS zone link | Route 53 private hosted zone association |
| DNS Private Resolver | Route 53 Resolver endpoints/rules |

This VM is the closest match to EC2, not Elastic Beanstalk. Azure App Service
remains the closer managed-platform analogue to Elastic Beanstalk; this lab
uses a VM because the subscription's App Service regional-worker quota was
zero.
