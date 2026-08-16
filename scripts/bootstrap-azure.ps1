[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$GitHubOwner,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepository,

    [ValidatePattern('^[a-z][a-z0-9]{2,11}$')]
    [string]$Prefix = 'ghazdemo',

    [string]$Location = 'eastus',

    [string]$SubscriptionId = '',

    [string]$PlanEnvironment = 'terraform-plan',

    [string]$ApplyEnvironment = 'development',

    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-LastExitCode {
    param([string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed while $Operation (exit code $LASTEXITCODE)."
    }
}

function Invoke-AzTsv {
    param([string[]]$AzArguments)

    $value = & az @AzArguments --only-show-errors --output tsv
    Assert-LastExitCode "running: az $($AzArguments -join ' ')"
    return ($value | Out-String).Trim()
}

# Azure CLI returns a nonzero exit code when an object does not exist. That is
# expected during an idempotent first-run check, but Windows PowerShell can turn
# native stderr into a terminating NativeCommandError when
# $ErrorActionPreference is Stop. Temporarily use Continue only for these
# existence probes, discard their expected error output, and return a Boolean.
function Test-AzObjectExists {
    param([string[]]$AzArguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & az @AzArguments --only-show-errors --output none 2>$null
        $commandExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return $commandExitCode -eq 0
}

function Ensure-RoleAssignment {
    param(
        [string]$PrincipalId,
        [string]$RoleName,
        [string]$Scope
    )

    $query = "[?roleDefinitionName=='$RoleName'] | [0].id"
    $existing = Invoke-AzTsv @(
        'role', 'assignment', 'list',
        '--assignee', $PrincipalId,
        '--scope', $Scope,
        '--query', $query
    )

    if (-not $existing) {
        Write-Host "Assigning '$RoleName' at $Scope"
        & az role assignment create `
            --assignee-object-id $PrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role $RoleName `
            --scope $Scope `
            --only-show-errors `
            --output none
        Assert-LastExitCode "assigning $RoleName"
    }
}

function Ensure-FederatedCredential {
    param(
        [string]$CredentialName,
        [string]$IdentityName,
        [string]$ResourceGroupName,
        [string]$Subject
    )

    $credentialExists = Test-AzObjectExists -AzArguments @(
        'identity', 'federated-credential', 'show',
        '--name', $CredentialName,
        '--identity-name', $IdentityName,
        '--resource-group', $ResourceGroupName
    )

    if (-not $credentialExists) {
        Write-Host "Creating federated credential '$CredentialName' for $Subject"
        & az identity federated-credential create `
            --name $CredentialName `
            --identity-name $IdentityName `
            --resource-group $ResourceGroupName `
            --issuer 'https://token.actions.githubusercontent.com' `
            --subject $Subject `
            --audiences 'api://AzureADTokenExchange' `
            --only-show-errors `
            --output none
        Assert-LastExitCode "creating federated credential $CredentialName"
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, run az login, and rerun this script.'
}

& az account show --only-show-errors --output none
Assert-LastExitCode 'checking the current Azure login'

if (-not $SubscriptionId) {
    $SubscriptionId = Invoke-AzTsv @('account', 'show', '--query', 'id')
}

& az account set --subscription $SubscriptionId --only-show-errors
Assert-LastExitCode 'selecting the Azure subscription'

$TenantId = Invoke-AzTsv @('account', 'show', '--query', 'tenantId')

# A deterministic suffix makes this bootstrap idempotent for one subscription
# and GitHub repository while keeping the Storage account globally distinctive.
$hashInput = "$SubscriptionId|$GitHubOwner|$GitHubRepository"
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
}
finally {
    $sha256.Dispose()
}
$Suffix = -join ($hashBytes[0..3] | ForEach-Object { $_.ToString('x2') })

$BootstrapResourceGroup = "rg-$Prefix-bootstrap"
$LabResourceGroup = "rg-$Prefix-dev"
$StateContainer = 'tfstate'
$StateStorageAccount = ("st{0}{1}" -f $Prefix, $Suffix).ToLowerInvariant()
if ($StateStorageAccount.Length -gt 24) {
    $StateStorageAccount = $StateStorageAccount.Substring(0, 24)
}
$PlanIdentityName = "id-$Prefix-gh-plan"
$ApplyIdentityName = "id-$Prefix-gh-apply"

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bootstrap-output.json'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

Write-Host 'Registering Azure resource providers used by the lab...'
foreach ($providerNamespace in @('Microsoft.ManagedIdentity', 'Microsoft.Network', 'Microsoft.Storage', 'Microsoft.Web')) {
    & az provider register --namespace $providerNamespace --wait --only-show-errors
    Assert-LastExitCode "registering $providerNamespace"
}

Write-Host 'Creating the bootstrap and lab resource groups...'
& az group create `
    --name $BootstrapResourceGroup `
    --location $Location `
    --tags managed-by=bootstrap purpose=azure-github-actions-learning-lab `
    --only-show-errors `
    --output none
Assert-LastExitCode 'creating the bootstrap resource group'

& az group create `
    --name $LabResourceGroup `
    --location $Location `
    --tags managed-by=terraform purpose=azure-github-actions-learning-lab `
    --only-show-errors `
    --output none
Assert-LastExitCode 'creating the lab resource group'

$stateAccountExists = Test-AzObjectExists -AzArguments @(
    'storage', 'account', 'show',
    '--name', $StateStorageAccount,
    '--resource-group', $BootstrapResourceGroup
)

if (-not $stateAccountExists) {
    Write-Host "Creating Terraform state account $StateStorageAccount..."
    & az storage account create `
        --name $StateStorageAccount `
        --resource-group $BootstrapResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --https-only true `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --allow-shared-key-access true `
        --public-network-access Enabled `
        --only-show-errors `
        --output none
    Assert-LastExitCode 'creating the Terraform state account'
}

# Shared-key access is used once to break the bootstrap cycle. The account is
# switched back to Entra-only authentication after the container exists.
$StateAccountKey = Invoke-AzTsv @(
    'storage', 'account', 'keys', 'list',
    '--resource-group', $BootstrapResourceGroup,
    '--account-name', $StateStorageAccount,
    '--query', '[0].value'
)

& az storage container create `
    --name $StateContainer `
    --account-name $StateStorageAccount `
    --account-key $StateAccountKey `
    --only-show-errors `
    --output none
Assert-LastExitCode 'creating the Terraform state container'
$StateAccountKey = $null

Write-Host 'Creating user-assigned managed identities...'
foreach ($identityName in @($PlanIdentityName, $ApplyIdentityName)) {
    $identityExists = Test-AzObjectExists -AzArguments @(
        'identity', 'show',
        '--name', $identityName,
        '--resource-group', $BootstrapResourceGroup
    )

    if (-not $identityExists) {
        & az identity create `
            --name $identityName `
            --resource-group $BootstrapResourceGroup `
            --location $Location `
            --only-show-errors `
            --output none
        Assert-LastExitCode "creating identity $identityName"
    }
}

$PlanClientId = Invoke-AzTsv @('identity', 'show', '--name', $PlanIdentityName, '--resource-group', $BootstrapResourceGroup, '--query', 'clientId')
$PlanPrincipalId = Invoke-AzTsv @('identity', 'show', '--name', $PlanIdentityName, '--resource-group', $BootstrapResourceGroup, '--query', 'principalId')
$ApplyClientId = Invoke-AzTsv @('identity', 'show', '--name', $ApplyIdentityName, '--resource-group', $BootstrapResourceGroup, '--query', 'clientId')
$ApplyPrincipalId = Invoke-AzTsv @('identity', 'show', '--name', $ApplyIdentityName, '--resource-group', $BootstrapResourceGroup, '--query', 'principalId')

$RepositorySubjectPrefix = "repo:$GitHubOwner/$GitHubRepository"
Ensure-FederatedCredential `
    -CredentialName 'github-plan-environment' `
    -IdentityName $PlanIdentityName `
    -ResourceGroupName $BootstrapResourceGroup `
    -Subject "${RepositorySubjectPrefix}:environment:$PlanEnvironment"

Ensure-FederatedCredential `
    -CredentialName 'github-apply-environment' `
    -IdentityName $ApplyIdentityName `
    -ResourceGroupName $BootstrapResourceGroup `
    -Subject "${RepositorySubjectPrefix}:environment:$ApplyEnvironment"

$LabResourceGroupId = Invoke-AzTsv @('group', 'show', '--name', $LabResourceGroup, '--query', 'id')
$StateStorageAccountId = Invoke-AzTsv @('storage', 'account', 'show', '--name', $StateStorageAccount, '--resource-group', $BootstrapResourceGroup, '--query', 'id')
$StateContainerScope = "$StateStorageAccountId/blobServices/default/containers/$StateContainer"

# The plan identity can inspect resources but cannot modify them. Both plan and
# apply need Blob Data Contributor narrowly on the state container because the
# Azure backend uses blob leases for state locking.
Ensure-RoleAssignment -PrincipalId $PlanPrincipalId -RoleName 'Reader' -Scope $LabResourceGroupId
Ensure-RoleAssignment -PrincipalId $PlanPrincipalId -RoleName 'Storage Blob Data Contributor' -Scope $StateContainerScope

# Contributor manages Azure resources but not RBAC. The second role exists only
# because this Terraform example creates managed-identity role assignments.
Ensure-RoleAssignment -PrincipalId $ApplyPrincipalId -RoleName 'Contributor' -Scope $LabResourceGroupId
Ensure-RoleAssignment -PrincipalId $ApplyPrincipalId -RoleName 'Role Based Access Control Administrator' -Scope $LabResourceGroupId
Ensure-RoleAssignment -PrincipalId $ApplyPrincipalId -RoleName 'Storage Blob Data Contributor' -Scope $StateContainerScope

& az storage account update `
    --name $StateStorageAccount `
    --resource-group $BootstrapResourceGroup `
    --allow-shared-key-access false `
    --only-show-errors `
    --output none
Assert-LastExitCode 'disabling shared-key access on the state account'

$BootstrapOutput = [ordered]@{
    github_owner              = $GitHubOwner
    github_repository         = $GitHubRepository
    subscription_id           = $SubscriptionId
    tenant_id                 = $TenantId
    location                  = $Location
    bootstrap_resource_group  = $BootstrapResourceGroup
    lab_resource_group        = $LabResourceGroup
    state_storage_account     = $StateStorageAccount
    state_container           = $StateContainer
    plan_identity_name        = $PlanIdentityName
    plan_client_id            = $PlanClientId
    apply_identity_name       = $ApplyIdentityName
    apply_client_id           = $ApplyClientId
    plan_environment          = $PlanEnvironment
    apply_environment         = $ApplyEnvironment
}

$BootstrapOutput | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host ''
Write-Host "Bootstrap completed. Non-secret identifiers were written to: $OutputPath"
Write-Host 'Azure RBAC and federated credentials may take several minutes to propagate.'
Write-Host 'Next: authenticate GitHub CLI, then run scripts/configure-github.ps1.'
