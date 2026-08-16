# Cost and cleanup

Azure prices vary by region and change over time. Use the
[Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
for current numbers before applying.

## Baseline billable resources

| Resource | Cost behavior | Why it exists |
|---|---|---|
| Linux App Service Plan B1 | Continuously billed | Managed compute and Elastic Beanstalk analogue |
| Three Private Endpoints | Hourly plus data | Private ingress for Blob and two web apps |
| Standard LRS Storage | Capacity/operations | Application Storage account |
| Private DNS zones | Zone/query based | Correct private service-name resolution |
| Terraform state Storage | Very small capacity/operations | Shared state and locking |

Both web apps share one App Service Plan. The second app does not create a
second plan charge, although both apps share the plan's capacity.

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

