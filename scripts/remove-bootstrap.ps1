[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('DESTROY-BOOTSTRAP')]
    [string]$Confirmation,

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
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to select the subscription recorded by bootstrap.'
}

Write-Host 'Deleting the lab and bootstrap resource groups. This also removes state and OIDC identities.'
Write-Host 'Use this only after the GitHub destroy workflow has removed Terraform-managed resources.'

foreach ($resourceGroupName in @($configuration.lab_resource_group, $configuration.bootstrap_resource_group)) {
    & az group delete `
        --name $resourceGroupName `
        --yes `
        --no-wait `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start deletion of resource group $resourceGroupName."
    }
}

Write-Host 'Deletion requests accepted. Azure completes them asynchronously.'

