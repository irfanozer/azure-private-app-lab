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

$configuration = Get-Content -LiteralPath $BootstrapOutputPath -Raw | ConvertFrom-Json
& az account set --subscription $configuration.subscription_id --only-show-errors

Write-Host 'Resources created by Terraform:'
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

