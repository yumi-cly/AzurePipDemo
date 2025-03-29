@description('The name of the Key Vault to create the key in.')
param vaultName string

@description('''
The name of the key to be created. New keys are configured to expire after 1 year 
from creation, auto-rotate 31-days prior to expiry, and notify 30-days prior to expiry.
''')
param keyName string

@description('The existing key. If specified, a new key is not created and the existing key is returned.')
param existingKey object = {}

@allowed([
  3072
  4096
])
@description('RSA Key size.')
param keySize int = 4096

@description('The base time of the deployment')
param baseTime string = utcNow()

var expiry = 'P1Y'
var expiryValue = dateTimeToEpoch(dateTimeAdd(baseTime, expiry))

resource vault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: vaultName
}

resource key 'Microsoft.KeyVault/vaults/keys@2022-07-01' = if (empty(existingKey)) {
  parent: vault
  name: keyName
  properties: {
    kty: 'RSA'
    keySize: keySize
    attributes: {
      enabled: true
      exp: expiryValue
    }
    rotationPolicy: {
      attributes: {
        expiryTime: expiry
      }
      lifetimeActions: [
        {
          action: {
            type: 'Rotate'
          }
          trigger: {
            timeBeforeExpiry: 'P31D'
          }
        }
        {
          action: {
            type: 'Notify'
          }
          trigger: {
            timeBeforeExpiry: 'P30D'
          }
        }
      ]
    }
  }
}

@description('The id of the Key Vault Key.')
output keyId string = (empty(existingKey)) ? key.id : existingKey.id

@description('The uri of the Key Vault Key.')
output keyUri string = (empty(existingKey)) ? key.properties.keyUri : existingKey.keyUri

@description('The uri with version of the Key Vault Key.')
output keyUriWithVersion string = (empty(existingKey)) ? key.properties.keyUriWithVersion : existingKey.keyUriWithVersion

@description('The name of the Key Vault Key.')
output keyName string = (empty(existingKey)) ? key.name : existingKey.name
