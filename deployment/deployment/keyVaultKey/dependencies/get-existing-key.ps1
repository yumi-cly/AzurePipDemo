param([string] $kvName, [string] $keyName)
      
$ErrorActionPreference = 'Stop'

$secureSpnKey = $Env:spnKey | ConvertTo-SecureString -AsPlainText -Force
$pscredential = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList $Env:spnId, $secureSpnKey

Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $Env:tenantId -SubscriptionId $Env:subId

if ($kvName -and $keyName) {
  Write-Host "Getting key vault via Get-AzKeyVault ... "
  $kvObj = $(Get-AzKeyVault -VaultName $kvName)
  
  if (!$kvObj) {
    Write-Host "The Key Vault ($kvName) was not found."
  }
  else {
    # wrap key lookup in access toggle - workaround due to bicep limitation (see https://github.com/Azure/bicep/issues/6540)
    $existingAccessSetting = $kvObj.PublicNetworkAccess

    Write-Host "Updating default access to Allow to enable host access to the Key Vault ... "
    Update-AzKeyVaultNetworkRuleSet -VaultName $kvName -DefaultAction Allow

    try {
      if ($existingAccessSetting -eq 'Disabled') {
        Write-Host "Enabling network access from select networks via Update-AzKeyVault ... "
        $kvObj | Update-AzKeyVault -PublicNetworkAccess 'Enabled'
      }
      
      $kvResourceGroupName = $kvObj.ResourceGroupName
      $kvScope = "/subscriptions/$Env:subId/resourcegroups/$kvResourceGroupName/providers/Microsoft.KeyVault/vaults/$kvName"

      # regular role assignment command will list role assignments at higher levels, need to filter the objects down to just the keyvault scope
      $spnObj = Get-AzADServicePrincipal -ApplicationId $Env:spnId
      $roleAssignmentName = "Key Vault Crypto User"

      Write-Host "Getting existing role assignment via Get-AzRoleAssignment ... "

      $roleAssignments = Get-AzRoleAssignment -Scope $kvScope | Where-Object {$_.Scope -eq $kvScope -and $_.ObjectId -eq $spnObj.Id -and $_.RoleDefinitionName -eq $roleAssignmentName}

      if ($kvObj.EnableRbacAuthorization -and $roleAssignments.Length -eq 0)
      {
        Write-Host "Adding role assignment via New-AzRoleAssignment ... "
        New-AzRoleAssignment -RoleDefinitionName $roleAssignmentName -ApplicationId $Env:spnId -Scope $kvScope
      }
      else
      {
        Write-Host "Setting access policies via Set-AzKeyVaultAccessPolicy ... "
        # Bicep-assigned access policies won't work here so have to do it like this. See https://azidentity.azurewebsites.net/post/2019/05/17/getting-it-right-key-vault-access-policies
        Set-AzKeyVaultAccessPolicy -VaultName $kvName -ServicePrincipalName $Env:spnId -PermissionsToKeys Get, List
      }

      # Allow time for role propagation
      Start-Sleep 15

      Write-Host "Getting KeyVault Key via Get-AzKeyVaultKey ... "
      $kvKey = $(Get-AzKeyVaultKey -VaultName $kvName -Name $keyName)
      
      if ($existingAccessSetting -eq 'Disabled') {
        Write-Host "Disabling network access ... "
        $kvObj | Update-AzKeyVault -PublicNetworkAccess Disabled
      }

      Write-Host "Updating default access to Deny ... "
      Update-AzKeyVaultNetworkRuleSet -VaultName $kvName -DefaultAction Deny
    }
    catch { 
        Write-Host "Error state. Updating default access to Deny ... "
        Update-AzKeyVaultNetworkRuleSet -VaultName $kvName -DefaultAction Deny 

      if ($existingAccessSetting -eq 'Disabled') {
        Write-Host "Error state. Disabling network access ... "
        $kvObj | Update-AzKeyVault -PublicNetworkAccess Disabled
      }
      
      throw
    }
    Write-Output $kvKey
    $keyId=$kvKey.Id
  }
}

$DeploymentScriptOutputs = @{}

$DeploymentScriptOutputs['keyUriWithVersion'] = (!$keyId) ? '' : $keyId
$DeploymentScriptOutputs['keyUri'] = (!$keyId) ? '' : $keyId.substring(0, $keyId.lastIndexOf('/'))
$DeploymentScriptOutputs['keyId'] = (!$keyId) ? '' : "/subscriptions/$Env:subId/resourceGroups/$($kvObj.ResourceGroupName)/providers/Microsoft.KeyVault/vaults/$kvName/keys/$keyName"
$DeploymentScriptOutputs['keyRgName'] = (!$keyId) ? '' : $kvObj.ResourceGroupName
$DeploymentScriptOutputs['keyName'] = (!$keyId) ? '' : $keyName