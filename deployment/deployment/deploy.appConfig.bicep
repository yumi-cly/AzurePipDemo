@description('(Optional). The location to deploy resources to')
param location string = resourceGroup().location

@description('(Optional).The target environment')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Dev'

@minLength(1)
@maxLength(2) // controls resource name length violations
@description('(Optional).The sequence number to use in the resource naming')
param sequenceNumber string = '01'

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('(Optional). The application name to use in the resource naming.')
param applicationName string = 'CLM'

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('(Optional). The department code to use in the resource naming.')
param departmentCode string = 'MCA'

@description('(Required). The id of the service principal')
param servicePrincipalId string

@description('(Required). The service principal key')
@secure()
param servicePrincipalKey string

@description('(Required). The resource group name in which all this is deployed.')
param resourceGroupName string

@description('Required. The blob service uri for the DMS account storage.')
param dmsStorageAccountName string

// pulls in a databse of premra's already installed shared services instances/names
var environmentMap = { dev: 'dv', staging: 'st', prod: 'pd' }

var resourceName = {
  applicationName: applicationName
  departmentCode: departmentCode
  environment: environmentMap[environment]
  sequenceNumber: sequenceNumber
}

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    location: location
    resourceName: resourceName
  }
}

module commonResources './modules/func-web-shared.bicep' = {
  name:'${uniqueString(deployment().name, location)}-fetchExistingStKv'
  params:{
    keyVaultName: resourceNames.outputs.resourceNames.kv
    resourceGroupName: resourceGroupName
    storageAccountName: resourceNames.outputs.resourceNames.st
  }
}

var var_identityName = toLower('id-${applicationName}-${departmentCode}-${environmentMap[environment]}-${location}-${sequenceNumber}')
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: var_identityName
}

// var cmkName = '${resourceNames.outputs.resourceNames.kv}-cmk'
var cmkName = 'keyEncryptionKey'

module appConfig './modules/app-configuration/deploy-appConfig.bicep' = {
  name: '${uniqueString(deployment().name, location)}-appConfig'
  params: {
    resourceName: resourceName
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
    location: location
    customerManagedKey: {
      keyName: cmkName
      keyVaultResourceId: commonResources.outputs.keyVaultResourceId
      userAssignedIdentityResourceId: userAssignedIdentity.id
    }
    managedIdentities: {
      userAssignedResourceIds: [ userAssignedIdentity.id ]
    }
    keyValues: [ {
      contentType: 'contentType'
      name: 'configKey1'
      value: 'configValue1'
    }
    {
      contentType: 'contentType'
      name: 'DMS_Storage_Conn_String__blobServiceUri'
      #disable-next-line no-hardcoded-env-urls
      value: 'https://${dmsStorageAccountName}.blob.core.windows.net/'
    }
    {
      contentType: 'contentType'
      name: 'DMS_Blob_Container_Name'
      value: 'documentsconfig'
    }
    {
      contentType: 'contentType'
      name: 'DMS_Blob_SubDir_Contract_WorkItems'
      value: 'input'
    }
    {
      contentType: 'contentType'
      name: 'MCA_KeyVault_Uri'
      #disable-next-line no-hardcoded-env-urls
      value: 'https://${resourceNames.outputs.resourceNames.kv}.vault.azure.net/'
    }
    ]
    roleAssignments: [ {
      principalId: userAssignedIdentity.properties.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'App Configuration Data Reader' 
    } ]
  }
}
