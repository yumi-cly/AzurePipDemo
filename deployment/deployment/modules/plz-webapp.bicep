@description('Required. Type of site to deploy.')
@allowed([
 'api'
  'app'
  'app,container,windows'
  'app,linux'
  'app,linux,container'
  'functionapp'
  'functionapp,linux'
  'functionapp,linux,container'
  'functionapp,linux,container,azurecontainerapps'
  'functionapp,workflowapp'
  'functionapp,workflowapp,linux'
  'linux,api'
])
param kind string = 'app'

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Optional. The .NET Framework version to use. Default: v8.0')
param netFrameworkVersion string = 'v8.0'

@description('Optional. The runtime stack. Default: dotnet:8')
param runtimeStack string = 'dotnet:8'

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

@description('Optional. Reference documentation can be found here: https://learn.microsoft.com/en-us/azure/app-service/reference-app-settings.')
param appSettingKeyValuePairs object = {
  ASPNETCORE_ENVIRONMENT: contains(['-staging', '-prod'], resourceName.environment) ? 'Production' : 'Development'
  // FUNCTIONS_EXTENSION_VERSION: '~4'
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

@description('Conditional. Required if enableHealthCheckMonitor is true. The health check path for the app.')
param healthCheckPath string?

var privateDnsZoneObj = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'webApp'))!
var eventHubObj = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'webApp'))!
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

module webApp 'br/public:avm/res/web/site:0.13.0' = {
  name: '${uniqueString(deployment().name, location)}-webApp'
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
    clientCertEnabled: null
    diagnosticSettings: diagnosticSettings
    enableTelemetry: false
    httpsOnly: true
    kind: kind
    location: location
    managedIdentities: managedIdentities
    name: resourceNames.outputs.resourceNames.app
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
      ftpsState: 'Disabled'
      healthCheckPath: healthCheckPath
      http20Enabled: true
      windowsFxVersion: runtimeStack
      minTlsVersion: '1.2'
      netFrameworkVersion: netFrameworkVersion
      privateEndPointNetworkPolicies: 'Enabled'
      remoteDebuggingEnabled: false
      storageAccountResourceId: storageAccountResourceId
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: 'dotnetcore'
        }
      ]
    }
    slots: empty(slotName) ? [] : [stagingSlot]
    virtualNetworkSubnetId: virtualNetworkSubnetId
    vnetContentShareEnabled: true
    vnetImagePullEnabled: true
    vnetRouteAllEnabled: true
    storageAccountUseIdentityAuthentication: true

  }
}

module metricAlert 'plz-insight-health-check.bicep' = if(enableHealthCheckMonitor) {
  name: '${uniqueString(deployment().name, location)}-metricAlertDeployment'
  params: {
    name: '${resourceNames.outputs.resourceNames.app} | Health Check | Alert'
    environment: resourceName.environment
    alertDescription: 'HealthCheck alert for the web app (${resourceNames.outputs.resourceNames.app})'
    alertCriteriaType: 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    scopes: [ webApp.outputs.resourceId ]
    targetResourceType: 'Microsoft.Web/sites'
  }
}

@description('The resource ID of the web app.')
output webAppResourceId string = webApp.outputs.resourceId

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = webApp.outputs.systemAssignedMIPrincipalId

@description('The resource id of the managed identity.')
output managedIdentityPrincipalId string = webApp.outputs.systemAssignedMIPrincipalId

type managedIdentitiesType = {
  @description('Optional. Enables system assigned managed identity on the resource.')
  systemAssigned: bool?

  @description('Optional. The resource ID(s) to assign to the resource.')
  userAssignedResourceIds: string[]?
}?
