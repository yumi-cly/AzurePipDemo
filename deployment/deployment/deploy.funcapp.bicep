@description('Optional. The location to deploy resources to')
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

@description('Required. The id of the service principal')
param servicePrincipalId string

@description('Required. The service principal key')
@secure()
param servicePrincipalKey string

@description('Conditional. Required when using integration subnet and private endpoint. Resource ID of the integration subnet to deploy the web app to.')
param virtualNetworkSubnetId string?

@description('Optional. Resource ID of the server farm (i.e. ASP) to deploy the web app to.')
param serverFarmResourceId string?

@description('Optional. Flag to enable the health check monitor.')
param enableHealthCheckMonitor bool = !empty(healthCheckPath) && (contains(subscription().displayName, '-prod'))

@description('Conditional. Required if enableHealthCheckMonitor is true. The health check path for the function app.')
param healthCheckPath string?

@description('Required. The resource group name in which all this is deployed.')
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

module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: '${uniqueString(deployment().name, location)}-umi'
  params: {
    name: resourceNames.outputs.resourceNames.id
    location: location
  }
}

module storageRoleAssignment './modules/role-assignment.bicep' = {
  name:'${uniqueString(deployment().name, location)}-roleAssignment-st'
  params: {
    location: location
    principalId:userAssignedIdentity.outputs.principalId
    resourceId: commonResources.outputs.storageAccountResourceId
    roleAssignments:[
      {
        roleDefinitionIdOrName: 'Storage Blob Data Owner'
        principalId: userAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalId: userAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: 'Storage Account Contributor'
        principalId: userAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

var keyVaultUri = 'https://${resourceNames.outputs.resourceNames.kv}${az.environment().suffixes.keyvaultDns}/'

module functionApp './modules/plz-functionapp.bicep' = {
  name: '${uniqueString(deployment().name, location)}-function'
  params: {
    resourceName: resourceName
    resourceGroupName: resourceGroupName
    location: location
    managedIdentities: {
      userAssignedResourceIds: [ userAssignedIdentity.outputs.resourceId ]
    }
    enableHealthCheckMonitor: enableHealthCheckMonitor
    healthCheckPath: healthCheckPath
    storageAccountResourceId: commonResources.outputs.storageAccountResourceId
    virtualNetworkSubnetId: virtualNetworkSubnetId
    serverFarmResourceId: serverFarmResourceId
    appSettingKeyValuePairs: {
      // APPINSIGHTS_INSTRUMENTATIONKEY: 
      AppConfigUri                              : 'https://${resourceNames.outputs.resourceNames.appcs}.azconfig.io'
      ASPNETCORE_ENVIRONMENT                    : contains(['staging', 'prod'], resourceName.environment) ? 'Production' : 'Development'
      FUNCTIONS_WORKER_RUNTIME                  : 'dotnet-isolated'
      FUNCTIONS_EXTENSION_VERSION               : '~4'
      WEBSITE_RUN_FROM_PACKAGE                  : '1'
      WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED    : '1'
      AZURE_CLIENT_ID                           : userAssignedIdentity.outputs.clientId
      AzureWebJobsFeatureFlags                  : 'EnableWorkerIndexing'
      AzureWebJobsStorage__accountname          : resourceNames.outputs.resourceNames.st
      AzureWebJobsStorage__clientId             : userAssignedIdentity.outputs.clientId
      AzureWebJobsStorage__credential           : 'managedidentity'
      DMS_Storage_Conn_String__accountName      : dmsStorageAccountName
      DMS_Storage_Conn_String__blobServiceUri   : 'https://${dmsStorageAccountName}.blob.${az.environment().suffixes.storage}/'
      DMS_Storage_Conn_String__queueServiceUri  : 'https://${dmsStorageAccountName}.queue.${az.environment().suffixes.storage}/'
      DMS_Blob_Container_Name                   : '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/DMSBlobContainerName/)'
      DMS_Blob_SubDir_Contract_WorkItems        : '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/DMSBlobSubDirContractWorkItems/)'
      DMSBlobTriggerPath                        : '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/DMSBlobTriggerPath/)'   
      MCA_KeyVault_Uri                          : keyVaultUri
    }
  }
}

@description('The resource ID of the function app.')
output functionAppResourceId string = functionApp.outputs.functionAppResourceId

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = functionApp.outputs.managedIdentityResourceId

@description('The resource id of the managed identity.')
output managedIdentityPrincipalId string = functionApp.outputs.managedIdentityPrincipalId
