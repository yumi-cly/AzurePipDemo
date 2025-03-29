@description('Required. Key vault name, use the keyVautlName module to generate this from resourceName object.')
param keyVaultName string

@description('''
The name of the key to be created. New keys are configured to expire after 1 year 
from creation, auto-rotate 31-days prior to expiry, and notify 30-days prior to expiry.
''')
param keyName string

@allowed([
  'new'
  'existing'
  ''
])
@description('''Optional. Indicates the provisioning state of the Key Vault Key. If not supplied, a 
lookup will be attempted using a custom deployment script. Default: \'\'.''')
param newOrExisting string = ''

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('''
Required. The id of the service principal that will be used to check on existing resource checks.
''')
param servicePrincipalId string

@description('''
Required. The service principal key for the servicePrincipalId parameter, will be used to check for existence of resources.
''')
@secure()
param servicePrincipalKey string

var buildPrefix = '${uniqueString(deployment().name, location)}_ExistingKeyVault'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = if(newOrExisting == 'existing') {
  name: keyVaultName
}

module keyLookup './get-existing-key.bicep' = if (empty(newOrExisting)) {
  name: '${buildPrefix}_existingCmk'
  params: {
    keyVaultName: keyVaultName
    keyName: keyName
    location: location
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
  }
  dependsOn: [
    keyVault
  ]
}

resource existingKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' existing = if ((newOrExisting != 'new' && (newOrExisting == 'existing' || keyLookup.outputs.keyExists))) {
  name: keyName
  parent: keyVault
}

@description('The URI of the Key.')
output keyUri string = empty(newOrExisting) ? keyLookup.outputs.keyUri : existingKey.properties.keyUri

@description('The uri with version of the Key Vault Key.')
output keyUriWithVersion string = (empty(newOrExisting)) ? keyLookup.outputs.keyUriWithVersion : existingKey.properties.keyUriWithVersion

@description('The resource id of the Key.')
output keyId string = empty(newOrExisting) ? keyLookup.outputs.keyId : existingKey.id

@description('The resource group name of the Key.')
output keyResourceGroupName string = resourceGroup().name

@description('The name of the Key Vault.')
output keyName string = empty(newOrExisting) ? keyLookup.outputs.keyName : existingKey.name

@description('Indicates if the Key Vault exists.')
output keyExists bool = empty(newOrExisting) ? keyLookup.outputs.keyExists : true


