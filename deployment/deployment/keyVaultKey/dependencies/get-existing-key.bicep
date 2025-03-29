@description('''
KeyVault name.
''')
param keyVaultName string

@description('''
Key name.
''')
param keyName string

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('''
The timestamp to use for the deployment script. Defaults to utcNow.
''')
param timeStamp string = utcNow()

@description('''
The id of the service principal. Requires contrib access to the Key Vault and Key get access

''')
param servicePrincipalId string

@description('''
The service principal key
''')
@secure()
param servicePrincipalKey string

@description('Optional. Tags to apply to the resource. Defaults to the resource group tags.')
param tags object = resourceGroup().tags

var buildPrefix = uniqueString(deployment().name, location)

// Performs an 'Get-AzKeyVaultKey' command to get the current version of a Key Vault key. 
// Empty output values are returned if the key is not found
resource getKeyVaultKey_script 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  #disable-next-line use-stable-resource-identifiers // non-deterministic value required to prevent deployment conflicts
  name: '${buildPrefix}_getKeyVaultKey'
  location: location
  kind: 'AzurePowerShell'
  tags: tags
  properties: {
    forceUpdateTag: timeStamp
    azPowerShellVersion: '11.0'
    timeout: 'PT10M'
    environmentVariables: [
      {
        name: 'tenantId'
        value: subscription().tenantId
      }
      {
        name: 'subId'
        value: subscription().subscriptionId
      }
      {
        name: 'spnId'
        value: servicePrincipalId
      }
      {
        name: 'spnKey'
        secureValue: servicePrincipalKey
      }
    ]
    arguments: '-kvName \\"${keyVaultName}\\" -keyName \\"${keyName}\\"'
    scriptContent: loadTextContent('./get-existing-key.ps1')
    cleanupPreference: 'Always'
    retentionInterval: 'PT1H'
  }
}

resource log 'Microsoft.Resources/deploymentScripts/logs@2023-08-01' existing = {
  parent: getKeyVaultKey_script
  name: 'default'
}

output keyUriWithVersion string = getKeyVaultKey_script.properties.outputs.keyUriWithVersion
output keyUri string = getKeyVaultKey_script.properties.outputs.keyUri
output keyId string = getKeyVaultKey_script.properties.outputs.keyId
output keyName string = getKeyVaultKey_script.properties.outputs.keyName
output keyResourceGroupName string = getKeyVaultKey_script.properties.outputs.keyRgName
output keyExists bool = (length(getKeyVaultKey_script.properties.outputs.keyName) > 2)
output logs string = log.properties.log
