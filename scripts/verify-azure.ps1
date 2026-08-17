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
Write-Host 'Linux VM, addresses, power state, and managed identity:'
& az vm list `
    --resource-group $configuration.lab_resource_group `
    --show-details `
    --query "[].{name:name,powerState:powerState,publicIp:publicIps,privateIp:privateIps,principalId:identity.principalId}" `
    --output table

Write-Host ''
Write-Host 'Inbound network rule (HTTP only; no SSH rule):'
$networkSecurityGroupName = (& az network nsg list `
        --resource-group $configuration.lab_resource_group `
        --query '[0].name' `
        --output tsv | Out-String).Trim()

if ($networkSecurityGroupName) {
    & az network nsg rule list `
        --resource-group $configuration.lab_resource_group `
        --nsg-name $networkSecurityGroupName `
        --query "[].{name:name,priority:priority,direction:direction,access:access,protocol:protocol,source:sourceAddressPrefix,destinationPort:destinationPortRange}" `
        --output table
}
else {
    Write-Host 'No VM network security group exists yet.'
}

Write-Host ''
Write-Host 'VM data-plane RBAC assignment on the private Storage account:'
$storageId = (& az storage account list `
        --resource-group $configuration.lab_resource_group `
        --query '[0].id' `
        --output tsv | Out-String).Trim()

if ($storageId) {
    & az role assignment list `
        --scope $storageId `
        --query "[?roleDefinitionName=='Storage Blob Data Contributor'].{principalId:principalId,role:roleDefinitionName,scope:scope}" `
        --output table
}

$publicIp = (& az network public-ip list `
        --resource-group $configuration.lab_resource_group `
        --query '[0].ipAddress' `
        --output tsv | Out-String).Trim()

Write-Host ''
if ($publicIp) {
    $browserUrl = "http://$publicIp"
    Write-Host "Browser URL: $browserUrl"
    Write-Host 'Testing the public Nginx page (cloud-init may need a few minutes after VM creation)...'

    try {
        $response = Invoke-WebRequest -Uri $browserUrl -UseBasicParsing -TimeoutSec 15
        Write-Host "HTTP test succeeded with status $($response.StatusCode)."
    }
    catch {
        Write-Warning "The VM exists, but the page is not ready yet: $($_.Exception.Message)"
    }
}
else {
    Write-Host 'No VM public IP exists yet. Run an approved Terraform apply first.'
}
