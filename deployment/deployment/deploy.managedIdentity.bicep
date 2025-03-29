@description('(Optional). The location to deploy resources to')
param location string = resourceGroup().location

@description('(Optional). The target environment')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Dev'

@description('(Optional). The application name to use in the resource naming.')
param applicationName string = 'CLM'

@minLength(1)
@maxLength(2) // controls resource name length violations
@description('(Optional). The sequence number to use in the resource naming. Default: 01')
param sequenceNumber string = '01'

@description('(Optional). The department code to use in the resource naming.')
param departmentCode string = 'MCA'

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

module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: '${uniqueString(deployment().name, location)}-umi'
  params: {
    name: resourceNames.outputs.resourceNames.id
    location: location
  }
}
