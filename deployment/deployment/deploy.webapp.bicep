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

// pulls in a databse of premra's already installed shared services instances/names
var environmentMap = { dev: 'dv', staging: 'st', prod: 'pd' }

var resourceName = {
  applicationName: applicationName
  departmentCode: departmentCode
  environment: environmentMap[environment]
  sequenceNumber: sequenceNumber
}

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
  }
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
    ]
  }
}

module webApp './modules/plz-webapp.bicep' = {
  name: '${uniqueString(deployment().name, location)}-web'
  params: {
    resourceName: resourceName
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
      ASPNETCORE_ENVIRONMENT: contains(['staging', 'prod'], toLower(resourceName.environment)) ? 'Production' : 'Development'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
      // FUNCTIONS_EXTENSION_VERSION: '~4'
    }
  }
}

@description('The resource ID of the web app.')
output webAppResourceId string = webApp.outputs.webAppResourceId

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = webApp.outputs.managedIdentityResourceId

@description('The resource id of the managed identity.')
output managedIdentityPrincipalId string = webApp.outputs.managedIdentityPrincipalId
