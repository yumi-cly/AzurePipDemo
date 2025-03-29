<#
.SYNOPSIS
    Calls a Network Services Api to create an integration subnet.

.NOTES
    At the time this script was created, the api is not idempotent and there is no published method
    exposed to determine if the request has already been run before. Due to this limitation, the 
    api cannot be used in unattended deployment scenarios.
#>

param(
    # AD Username (ex: us12345)
    [Parameter(Mandatory = $true)]
    [string] $UserName,

    # Team Email Address of group requesting Subnet (ex: teamname@premera.com)
    [Parameter(Mandatory = $true)]
    [string] $Email,

    # Application Name (ex: Siebel_Dev)
    [Parameter(Mandatory = $true)]
    [string] $AppName,

    # Environment of Subnet (ex: Dev)
    [Parameter(Mandatory = $true)]
    [ValidateSet("Dev", "Test", "Staging", "Prod", "Validation")]
    [string] $Environment,

    # Service Now Application ID Number (ex: SNSVC0019476)
    [Parameter(Mandatory = $true)]
    [string] $ServiceNowAppId
)

$ErrorActionPreference = 'Stop'

$uri = "http://nssites.corp.premera.org:8000/integrationsubnet/"

$body = @"
{
    "app_username": "$UserName",
    "app_email": "$Email",
    "app_application": "$AppName",
    "app_environment": "$Environment",
    "app_code": "$ServiceNowAppId"
}
"@

$response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers @{Accept = 'application/json'} -ContentType "application/json"

Write-Host "Response: $($response | ConvertTo-Json -Depth 5)"

return "/subscriptions/$($response.AZSubscription)/resourceGroups/$($response.AZResourceGroup)/providers/Microsoft.Network/virtualNetworks/$($response.AZVnetName)/subnets/$($response.AZSubnetName)"
 