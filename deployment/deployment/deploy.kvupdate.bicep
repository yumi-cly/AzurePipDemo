@description('The location to deploy resources to')
param location string = resourceGroup().location

@description('The target environment')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Dev'

@minLength(1)
@maxLength(2) // controls resource name length violations
@description('The sequence number to use in the resource naming')
param sequenceNumber string = '01'

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('Required. The application name to use in the resource naming.')
param applicationName string = 'CLM'

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('The department code to use in the resource naming.')
param departmentCode string = 'MCA'

@description('The base time of the deployment')
param baseTime string = utcNow()

@description('DMSBlobContainerName')
param DMSBlobContainerName string = ''

@description('DMSBlobSubDirContractWorkItems')
param DMSBlobSubDirContractWorkItems string = ''

@description('DMSBlobTriggerPath')
param DMSBlobTriggerPath string = ''

@description('ironcladClientSecret')
@secure()
param ironcladClientSecret string = ''


var environmentMap = { dev: 'dv', staging: 'st', prod: 'pd' }
var regionMap = {westus2: 'w2', southcentralus: 'sc'}

var resourceName = {
  applicationName: applicationName
  departmentCode: departmentCode
  environment: environmentMap[environment]
  sequenceNumber: sequenceNumber
}

var keyVaultName = toLower('kv${resourceName.applicationName}${resourceName.departmentCode}${environmentMap[environment]}${regionMap[location]}${resourceName.sequenceNumber}')

// Start Add Secret
module keyVaultSecret './secrets/keyvaultsecret.bicep' = {
  name: '${uniqueString(deployment().name, location)}-keyContainerName'
  params: {
    vaultName: keyVaultName
    secretName: 'DMSBlobContainerName'
    secretValue: DMSBlobContainerName
    attributesExp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  }
}

module kvSecretSubDirContractWI './secrets/keyvaultsecret.bicep' = {
  name: '${uniqueString(deployment().name, location)}-secretDirWorkItems'
  params: {
    vaultName: keyVaultName
    secretName: 'DMSBlobSubDirContractWorkItems'
    secretValue: DMSBlobSubDirContractWorkItems
    attributesExp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  }
}

module kvSecretDMSBlobTriggerPath './secrets/keyvaultsecret.bicep' = {
  name: '${uniqueString(deployment().name, location)}-secretDMSBlobTriggerPath'
  params: {
    vaultName: keyVaultName
    secretName: 'DMSBlobTriggerPath'
    secretValue: DMSBlobTriggerPath
    attributesExp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  }
}

module kvSecretIroncladClientSecret './secrets/keyvaultsecret.bicep' = {
  name: '${uniqueString(deployment().name, location)}-secretironcladClientSecret'
  params: {
    vaultName: keyVaultName
    secretName: 'ironcladClientSecret'
    secretValue: ironcladClientSecret
    attributesExp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  }
}


//End Add Secret
