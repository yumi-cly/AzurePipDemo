@description('Required. Type of site to deploy.')
@allowed([
  'functionapp' // function app windows os
  'functionapp,linux' // function app linux os
  'functionapp,workflowapp' // logic app
  'functionapp,workflowapp,linux' // logic app docker container
  'app' // web app
])
param kind string = 'functionapp'

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('''
Required. An object containing properties required to construct compliant resource names. 
The sum of the length of these parameters shouldn't exceed the maximum length allowed by the 
resource(s) that are deployed. Refer to the Azure documentation for details on length restrictions.

Custom object:
- applicationName: Required. The name of the application.
- departmentCode: Required. The department code.
- environment: Required. The environment name.
- sequenceNumber: Required. The sequence number.
naming convention for the resource's region name is used.
''')
param resourceName object

@description('Optional. Resource Id of the App Service Plan. If not provided, one is created.')
param serverFarmResourceId string?

@description('Optional. Name of the slot to deploy the web app to. Default: staging.')
param slotName string = 'staging'

@description('''Conditional. Required when using private endpoint instead using an ASE-hosted App Service Plan. 
Resource ID of the integration subnet to deploy the web app to.''')
param virtualNetworkSubnetId string?

@description('Optional. The .NET framework version.')
param dotNetFrameworkVersion string = 'v8.0'

@description('Optional. Reference documentation can be found here: https://learn.microsoft.com/en-us/azure/app-service/reference-app-settings.')
param appSettingKeyValuePairs object = {
  ASPNETCORE_ENVIRONMENT: contains(['-staging', '-prod'], resourceName.environment) ? 'Production' : 'Development'
  FUNCTIONS_EXTENSION_VERSION: '~4'
  FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
  remoteDebuggingEnabled: false
}

@description('Required. The resource ID of the storage account.')
param storageAccountResourceId string

@description('''Optional. The managed identity definition for this resource. Type definition:

type managedIdentitiesType = {
  @description('Optional. Enables system assigned managed identity on the resource.')
  systemAssigned: bool?

  @description('Optional. The resource ID(s) to assign to the resource.')
  userAssignedResourceIds: string[]?
}?
''')
param managedIdentities object = { systemAssigned: true }

@description('Optional. Flag to enable the health check monitor.')
param enableHealthCheckMonitor bool = !empty(healthCheckPath) && (contains(subscription().displayName, '-prod'))

@description('Conditional. Required if enableHealthCheckMonitor is true. The health check path for the function app.')
param healthCheckPath string?

@description('Required. The resource group name in which all this is deployed.')
param resourceGroupName string

var privateDnsZoneObj = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'funcApp'))!
var eventHubObj = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'funcApp'))!
var stagingSlot = { 
  name: slotName
  appInsightResourceId: appInsights.outputs.resourceId
  publicNetworkAccess: 'Disabled'
  privateEndpoints: empty(virtualNetworkSubnetId) ? [] : [
    {
      enableTelemetry: false
      privateDnsZoneGroup: {
        privateDnsZoneGroupConfigs: [{
          privateDnsZoneResourceId: privateDnsZoneObj.id
        }]
      }
      location: location
      subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
    }
  ]
  vnetContentShareEnabled: true
  vnetImagePullEnabled: true
  vnetRouteAllEnabled: true
}
var diagnosticSettings = [
  {
    eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
    eventHubName: eventHubObj.name
  }
]

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    resourceName: resourceName
  }
}

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
  }
}

module appInsights 'br/public:avm/res/insights/component:0.4.0' = {
  name: '${uniqueString(deployment().name, location)}-appi'
  params: {
    location: location
    name: resourceNames.outputs.resourceNames.appi
    enableTelemetry: false
    applicationType: 'web'
    kind: 'web'
    workspaceResourceId: sharedResources.outputs.sharedLogAnalyticsWorkspaceObj.id
    diagnosticSettings: diagnosticSettings
  }
}

module appServicePlan 'plz-server-farm.bicep' = if(empty(serverFarmResourceId)) {
  name: '${uniqueString(deployment().name, location)}-asp'
  params: {
    location: location
    resourceNameObj: resourceName
  }
}

module commonResource './func-web-shared.bicep' = {
  name: '${uniqueString(deployment().name, location)}-commonResource'
  params: {
    resourceGroupName: resourceGroupName
    storageAccountName: resourceNames.outputs.resourceNames.st
    keyVaultName: resourceNames.outputs.resourceNames.kv
    managedIdentityName: resourceNames.outputs.resourceNames.id
  }
}

module funcApp 'br/public:avm/res/web/site:0.13.0' = {
  name: '${uniqueString(deployment().name, location)}-funcApp'
  params: {
    appInsightResourceId: appInsights.outputs.resourceId
    appSettingsKeyValuePairs: appSettingKeyValuePairs
    basicPublishingCredentialsPolicies: [
      {
        allow: false
        name: 'ftp'
      }
      {
        allow: false
        name: 'scm'
      }
    ]
    clientAffinityEnabled: false
    clientCertEnabled: true
    diagnosticSettings: diagnosticSettings
    enableTelemetry: false
    httpsOnly: true
    kind: kind
    location: location
    managedIdentities: managedIdentities
    keyVaultAccessIdentityResourceId: commonResource.outputs.managedIdentityResourceId
    name: resourceNames.outputs.resourceNames.func
    publicNetworkAccess: empty(virtualNetworkSubnetId) ? 'Enabled' : 'Disabled' // If not using private endpoints, set to 'Enabled' to prevent `Ip Forbidden (CODE: 403)` during deployment.
    privateEndpoints: empty(virtualNetworkSubnetId) ? [] : [
      {
        enableTelemetry: false
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [{
            privateDnsZoneResourceId: privateDnsZoneObj.id
          }]
        }
        location: location
        subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
      }
    ]
    scmSiteAlsoStopped: true
    serverFarmResourceId: empty(serverFarmResourceId) ? appServicePlan.outputs.resourceId : serverFarmResourceId!
    siteConfig: {
      alwaysOn: contains(['dev', 'test'], toLower(resourceName.environment)) ? false : true
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'vnetrouteallenabled'
          value: '1'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.outputs.instrumentationKey
        }
      ]
      healthCheckPath: healthCheckPath
      http20Enabled: true
      minTlsVersion: '1.2'
      netFrameworkVersion: dotNetFrameworkVersion
      privateEndPointNetworkPolicies: 'Enabled'
      remoteDebuggingEnabled: false
      storageAccountResourceId: storageAccountResourceId
    }
    slots: empty(slotName) ? [] : [stagingSlot]
    virtualNetworkSubnetId: virtualNetworkSubnetId
    vnetContentShareEnabled: true
    vnetImagePullEnabled: true
    vnetRouteAllEnabled: true
    storageAccountUseIdentityAuthentication: true
  }
}

module metricAlert './plz-insight-health-check.bicep' = if(enableHealthCheckMonitor) {
  name: '${uniqueString(deployment().name, location)}-metricAlertDeployment'
  params: {
    name: '${resourceNames.outputs.resourceNames.func} | Health Check | Alert'
    environment: resourceName.environment
    alertDescription: 'HealthCheck alert for the function app (${resourceNames.outputs.resourceNames.func})'
    alertCriteriaType: 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    scopes: [ funcApp.outputs.resourceId ]
    targetResourceType: 'Microsoft.Web/sites'
  }
}

@description('The resource ID of the function app.')
output functionAppResourceId string = funcApp.outputs.resourceId

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = funcApp.outputs.systemAssignedMIPrincipalId

@description('The resource id of the managed identity.')
output managedIdentityPrincipalId string = funcApp.outputs.systemAssignedMIPrincipalId

type managedIdentitiesType = {
  @description('Optional. Enables system assigned managed identity on the resource.')
  systemAssigned: bool?

  @description('Optional. The resource ID(s) to assign to the resource.')
  userAssignedResourceIds: string[]?
}?
