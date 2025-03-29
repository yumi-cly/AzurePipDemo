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

@description('(Required). The Azure AD id of a group to grant privileged key vault roles to.')
param groupObjectId string

@description('The base time of the deployment')
param baseTime string = utcNow()

// pulls in a databse of premra's already installed shared services instances/names
var environmentMap = { dev: 'dv', staging: 'st', prod: 'pd' }

var resourceName = {
  applicationName: applicationName
  departmentCode: departmentCode
  environment: environmentMap[environment]
  sequenceNumber: sequenceNumber
}

var diagEventHubKeyVault = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'keyVault'))!
var privateDnsZoneObjKeyVault = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'keyVault'))!
var privateEndpointObj = sharedResources.outputs.sharedPrivateEndpointObj
var logAnalyticsWorkspaceObj = sharedResources.outputs.sharedLogAnalyticsWorkspaceObj
var logAnalyticsWorkspaceId = resourceId(logAnalyticsWorkspaceObj.subscriptionId, logAnalyticsWorkspaceObj.resourceGroupName, 'Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceObj.workspaceName)

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    location: location
    resourceName: resourceName
  }
}

// pulls in a databse of premra's already installed shared services instances/names
module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
  }
}

var var_identityName = toLower('id-${applicationName}-${departmentCode}-${environmentMap[environment]}-${location}-${sequenceNumber}')

var newVariable = {
  name: 'keyEncryptionKey'
  kty: 'RSA'
  attributesExp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  attributes: {
    enabled: true
    exp: dateTimeToEpoch(dateTimeAdd(baseTime, 'P10Y'))
  }
}
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: var_identityName
}

module shared 'modules/func-web-shared.bicep' = {
  name: '${uniqueString(deployment().name, location)}-fetchExistingStKv'
  params: {
    storageAccountName: resourceNames.outputs.resourceNames.st
    keyVaultName: resourceNames.outputs.resourceNames.kv
    resourceGroupName: resourceGroup().name
  }
}

var existingKey = shared.outputs.keyVaultKeyResourceId

module keyVault 'br/public:avm/res/key-vault/vault:0.11.2' = {
  name: '${uniqueString(deployment().name, location)}-KeyVault'
  params: {
    name: resourceNames.outputs.resourceNames.kv
    diagnosticSettings: [
      {
        name: '${resourceNames.outputs.resourceNames.kv}-diag'
        workspaceResourceId: logAnalyticsWorkspaceId
        eventHubAuthorizationRuleResourceId: diagEventHubKeyVault.authorizationRuleId
        eventHubName: diagEventHubKeyVault.name
        metricCategories: [{ category: 'AllMetrics', enabled: true }]
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs', enabled: true }, { categoryGroup: 'audit', enabled: true }]
      }
    ]
    enableTelemetry: false
    location: location
    enablePurgeProtection: true
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
    enableVaultForDeployment: true
    accessPolicies: []
    keys: empty(existingKey) ? [newVariable] : []
    sku: 'standard'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
      bypass: 'AzureServices'
    }
    enableVaultForTemplateDeployment: true
    publicNetworkAccess: 'Disabled'
    roleAssignments: [
      {
        principalId: managedIdentity.properties.principalId
        roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424') // Key Vault Crypto User
        principalType: 'ServicePrincipal'
      }
      {
        principalId: managedIdentity.properties.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Certificate User'
      }
      {
        principalId: groupObjectId
        principalType: 'Group'
        // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-officer
        roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
      }
      {
        principalId: groupObjectId
        principalType: 'Group'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
      {
        principalId: groupObjectId
        principalType: 'Group'
        roleDefinitionIdOrName: 'Key Vault Reader'
      }
    ]
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneObjKeyVault.id
            }
          ]
        }
        subnetResourceId: privateEndpointObj.subnetId
      }
    ]
  }
}