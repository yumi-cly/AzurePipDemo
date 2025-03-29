// https://dev.azure.com/pbc/Premera/_git/ECP_ResourceModules?path=/src/modules/keyVaultKey/deploy.bicep

@description('Required. The name of the Key Vault to create the key in.')
param vaultName string

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Optional. The name of the resource group the keyvault exists in.')
param vaultResourceGroupName string = resourceGroup().name

@description('''
Required. The name of the key to be created. New keys are configured to expire after 1 year 
from creation, auto-rotate 31-days prior to expiry, and notify 30-days prior to expiry.
''')
param keyName string

@description('[Deprecated]. This property is not used and will be removed in a future version.')
#disable-next-line no-unused-params // deprecated parameter is not used.
param existingKey object = {}

@allowed([
  3072
  4096
])
@description('Optional. RSA Key size. Default: 4096.')
param keySize int = 4096

@description('Optional. The base time of the deployment.')
param baseTime string = utcNow()

@allowed([
  'new'
  'existing'
  ''
])
@description('''Optional. Indicates the provisioning state of the Key Vault Key. If not supplied, a 
lookup will be attempted using a custom deployment script. Default: \'\'.''')
param newOrExisting string = ''

@description('''
Required. The id of the service principal that will be used to check on existing resource checks.
''')
param servicePrincipalId string

@description('''
Required. The service principal key for the servicePrincipalId parameter, will be used to check for existence of resources.
''')
@secure()
param servicePrincipalKey string

var buildPrefix = '${uniqueString(deployment().name, location)}_keyVault'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: vaultName
}

module existingKeyResource './dependencies/check-existing-key.bicep' = {
  name: '${buildPrefix}_key'
  params: {
    location: location
    keyVaultName: vaultName
    keyName: keyName
    newOrExisting: newOrExisting
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
  }
}

module keyVaultKey './dependencies/new-key.bicep' = {
  name: buildPrefix
  scope: resourceGroup(vaultResourceGroupName)
  params: {
    vaultName: keyVault.name
    keyName: keyName
    existingKey: (newOrExisting != 'new' && existingKeyResource.outputs.keyExists)
      ? {
          name: existingKeyResource.outputs.keyName
          keyUri: existingKeyResource.outputs.keyUri
          keyUriWithVersion: existingKeyResource.outputs.keyUriWithVersion
          id: existingKeyResource.outputs.keyId
        }
      : {}
    keySize: keySize
    baseTime: baseTime
  }
  dependsOn: [existingKeyResource]
}

@description('The id of the Key Vault Key.')
output keyId string = keyVaultKey.outputs.keyId

@description('The uri of the Key Vault Key.')
output keyUri string = keyVaultKey.outputs.keyUri

@description('The uri with version of the Key Vault Key.')
output keyUriWithVersion string = keyVaultKey.outputs.keyUriWithVersion

@description('The name of the Key Vault Key.')
output keyName string = keyVaultKey.outputs.keyName
