# Cost and cleanup

Azure prices vary by region and change over time. Use the
[Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
for current numbers before applying.

## Baseline billable resources

| Resource | Cost behavior | Why it exists |
|---|---|---|
| Linux VM (`Standard_F1als_v7` by default) | Billed while allocated | Browser-visible Nginx compute and EC2-style IaaS lesson |
| Managed OS disk | Capacity based, including when VM is stopped | Persistent Ubuntu operating-system disk |
| Standard Public IPv4 | Can be billed while allocated | Explicit inbound HTTP and outbound package path |
| One Blob Private Endpoint | Hourly plus data | Private Storage data-plane path |
| Standard LRS Storage | Capacity/operations | Application Storage account |
| One Private DNS zone | Zone/query based | Correct private Blob name resolution |
| Terraform state Storage | Very small capacity/operations | Shared state and locking |

Stopping/deallocating the VM stops its compute charge, but the managed disk,
Public IP, Private Endpoint, Storage, and DNS can still be billed. Terraform
destroy is the reliable end-of-lab cleanup.

## Optional expensive resources

Azure DNS Private Resolver inbound and outbound endpoints are continuously
billed. They are disabled by default because same-VNet resources using
Azure-provided DNS and linked zones do not need a resolver.

Set `ENABLE_PRIVATE_DNS_RESOLVER=true` only while studying hybrid DNS. Set it
back to `false` and apply as soon as you finish.

## Cleanup order

1. Run the **Destroy Azure learning lab** workflow.
2. Enter `DESTROY`.
3. Review the destroy plan.
4. Approve the `development` Environment.
5. Confirm Terraform completed successfully.
6. Run:

   ```powershell
   ./scripts/remove-bootstrap.ps1 -Confirmation DESTROY-BOOTSTRAP
   ```

Terraform destroys the application resources first while its state and apply
identity still exist. The final script then deletes the bootstrap resource
group, including the remote state account and both GitHub deployment identities,
and deletes the now-empty lab resource group.

## If the pipeline is broken

Prefer repairing the workflow and running Terraform destroy, because that keeps
state correct. For a disposable lab only, the Azure resource groups are the
recovery boundary. The bootstrap output records their exact names. Deleting the
groups directly removes the Azure resources but leaves Terraform state stale
until the state account is also deleted.

Never reuse this cleanup pattern for a shared or production resource group.
