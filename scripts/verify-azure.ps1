[CmdletBinding()]
param(
    [string]$BootstrapOutputPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found.'
}

if (-not $BootstrapOutputPath) {
    $BootstrapOutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bootstrap-output.json'
}

if (-not (Test-Path -LiteralPath $BootstrapOutputPath)) {
    throw "Bootstrap output was not found: $BootstrapOutputPath. Complete bootstrap-azure.ps1 first."
}

$configuration = Get-Content -LiteralPath $BootstrapOutputPath -Raw | ConvertFrom-Json
& az account set --subscription $configuration.subscription_id --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI could not select the bootstrapped subscription.'
}

Write-Host 'Bootstrap resources (state and GitHub deployment identities):'
& az resource list `
    --resource-group $configuration.bootstrap_resource_group `
    --query "[].{name:name,type:type,location:location}" `
    --output table

Write-Host ''
Write-Host 'Terraform state account security settings:'
& az storage account show `
    --name $configuration.state_storage_account `
    --resource-group $configuration.bootstrap_resource_group `
    --query "{name:name,publicNetworkAccess:publicNetworkAccess,sharedKeyAccess:allowSharedKeyAccess,httpsOnly:enableHttpsTrafficOnly,minTls:minimumTlsVersion}" `
    --output table

Write-Host ''
Write-Host 'GitHub OIDC federated credentials:'
foreach ($identity in @(
        @{ Name = $configuration.plan_identity_name; Label = 'Plan identity' },
        @{ Name = $configuration.apply_identity_name; Label = 'Apply identity' }
    )) {
    Write-Host $identity.Label
    & az identity federated-credential list `
        --identity-name $identity.Name `
        --resource-group $configuration.bootstrap_resource_group `
        --query "[].{name:name,issuer:issuer,subject:subject,audiences:audiences}" `
        --output table
}

Write-Host ''
Write-Host 'Resources created by Terraform (empty before the first approved apply):'
& az resource list `
    --resource-group $configuration.lab_resource_group `
    --query "[].{name:name,type:type,location:location}" `
    --output table

Write-Host ''
Write-Host 'Private Endpoints and connection state:'
& az network private-endpoint list `
    --resource-group $configuration.lab_resource_group `
    --query "[].{name:name,subnet:subnet.id,connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" `
    --output table

Write-Host ''
Write-Host 'Private DNS zones:'
& az network private-dns zone list `
    --resource-group $configuration.lab_resource_group `
    --query "[].{name:name,records:numberOfRecordSets}" `
    --output table

Write-Host ''
Write-Host 'Web App managed identities:'
& az webapp list `
    --resource-group $configuration.lab_resource_group `
    --query "[].{name:name,principalId:identity.principalId,publicNetworkAccess:publicNetworkAccess,hostname:defaultHostName}" `
    --output table

Write-Host ''
Write-Host 'The apps are private-only. A public laptop or GitHub-hosted runner should not be able to curl them.'
Write-Host 'Use a VNet-connected test host and the normal *.azurewebsites.net hostname to test private DNS and TLS.'
