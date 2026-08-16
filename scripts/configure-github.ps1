[CmdletBinding()]
param(
    [string]$BootstrapOutputPath = '',
    [string]$Repository = ''
)

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode {
    param([string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI failed while $Operation (exit code $LASTEXITCODE)."
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI was not found. Install it, run gh auth login, and rerun this script.'
}

if (-not $BootstrapOutputPath) {
    $BootstrapOutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bootstrap-output.json'
}

$BootstrapOutputPath = [System.IO.Path]::GetFullPath($BootstrapOutputPath)
if (-not (Test-Path -LiteralPath $BootstrapOutputPath)) {
    throw "Bootstrap output was not found: $BootstrapOutputPath"
}

$configuration = Get-Content -LiteralPath $BootstrapOutputPath -Raw | ConvertFrom-Json

if (-not $Repository) {
    $Repository = "$($configuration.github_owner)/$($configuration.github_repository)"
}

& gh auth status
Assert-LastExitCode 'checking authentication'

Write-Host "Creating GitHub Environments in $Repository..."
foreach ($environmentName in @($configuration.plan_environment, $configuration.apply_environment)) {
    & gh api `
        --method PUT `
        -H 'Accept: application/vnd.github+json' `
        "repos/$Repository/environments/$environmentName" `
        --silent
    Assert-LastExitCode "creating environment $environmentName"
}

$variables = [ordered]@{
    AZURE_TENANT_ID                  = $configuration.tenant_id
    AZURE_SUBSCRIPTION_ID            = $configuration.subscription_id
    AZURE_PLAN_CLIENT_ID             = $configuration.plan_client_id
    AZURE_APPLY_CLIENT_ID            = $configuration.apply_client_id
    AZURE_LAB_RESOURCE_GROUP         = $configuration.lab_resource_group
    TF_STATE_STORAGE_ACCOUNT         = $configuration.state_storage_account
    TF_STATE_CONTAINER               = $configuration.state_container
    ENABLE_PRIVATE_DNS_RESOLVER      = 'false'
}

Write-Host 'Setting repository variables (these are identifiers, not passwords)...'
foreach ($entry in $variables.GetEnumerator()) {
    & gh variable set $entry.Key `
        --body ([string]$entry.Value) `
        --repo $Repository
    Assert-LastExitCode "setting variable $($entry.Key)"
}

Write-Host ''
Write-Host 'GitHub configuration completed.'
Write-Host "Important manual step: protect the '$($configuration.apply_environment)' environment with a required reviewer and restrict it to main."
Write-Host 'No Azure client secret was created or stored.'

