metadata name = 'App Service Plan'
metadata description = 'This module deploys an App Service Plan.'

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
param resourceNameObj object

@description('Required. Defines the name, tier, size, family and capacity of the App Service Plan.')
@metadata({
  example: '''
  {
    name: 'P2v3'
    tier: 'Premium'
    size: 'P2v3'
    family: 'P'
    capacity: 1
  }
  '''
})
param sku object = {
  name: 'P2v3'
  tier: 'Premium'
  size: 'P2v3'
  family: 'P'
  capacity: contains(['-staging', '-prod'], resourceNameObj.environment) ? 2 : 1
}

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Scaling worker count.')
param targetWorkerCount int = 0

@description('Optional. The instance size of the hosting plan (small, medium, or large).')
@allowed([
  0
  1
  2
])
param targetWorkerSize int = 0

@description('Optional. ')
param zoneRedundant bool = false

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    resourceName: {
      applicationName: resourceNameObj.applicationName
      departmentCode: resourceNameObj.departmentCode
      environment: resourceNameObj.environment
      sequenceNumber: resourceNameObj.sequenceNumber
    }
  }
}

module serverfarm 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: '${uniqueString(deployment().name, location)}-asp'
  params: {
    name: resourceNames.outputs.asp
    sku: sku
    location: location
    targetWorkerCount: targetWorkerCount
    targetWorkerSize: targetWorkerSize
    zoneRedundant: zoneRedundant
  }
}

@description('The resource ID of the app service plan.')
output resourceId string = serverfarm.outputs.resourceId
