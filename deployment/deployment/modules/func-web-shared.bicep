param storageAccountName string
param keyVaultName string
param resourceGroupName string
param managedIdentityName string = ''

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
  scope: resourceGroup(resourceGroupName)
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(resourceGroupName)
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
  scope: resourceGroup(resourceGroupName)
}

resource existingKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' existing = {
  name: 'keyEncryptionKey'
  parent: keyVault
}

output storageAccountResourceId string = storageAccount.id
output keyVaultResourceId string = keyVault.id
output managedIdentityResourceId string = managedIdentity.id
output keyVaultKeyResourceId string = existingKey.id
