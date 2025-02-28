@description('The location to deploy resources to')
param location string = resourceGroup().location

@description('The target environment')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Dev'

@description('The application name to use in the resource naming.')
param applicationName string = 'CLM'

@minLength(1)
@maxLength(2) // controls resource name length violations
@description('Optional. The sequence number to use in the resource naming. Default: 01')
param sequenceNumber string = '01'

@description('The department code to use in the resource naming.')
param departmentCode string = 'MCA'

// @description('Required. Object representing segments of a PLZ-compliant resource name.')
// param resourceName object

// @description('Optional. The base time of the deployment.')
// param baseTime string = utcNow()

@maxLength(24)
@description('Optional. Unique identifier for the deployment. Will appear in resource names. Must be 24 characters or less.')
param identifier string

@description('The Azure AD id of a group to grant privileged key vault roles to.')
param groupObjectId string


output sequenceNumber_var string = sequenceNumber
output departmentCode_var string = departmentCode
output applicationName_var string = applicationName

output location_var string = location
output identifier_var string = identifier
output groupObjectId_param string = groupObjectId
//output resourceName_param object = resourceName

var diagEventHubKeyVault = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'keyVault'))!
var privateDnsZoneObj = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'keyVault'))!
var privateEndpointObj = sharedResources.outputs.sharedPrivateEndpointObj
var logAnalyticsWorkspaceObj = sharedResources.outputs.sharedLogAnalyticsWorkspaceObj
var logAnalyticsWorkspaceId = resourceId(logAnalyticsWorkspaceObj.subscriptionId, logAnalyticsWorkspaceObj.resourceGroupName, 'Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceObj.workspaceName)

// pulls in a databse of premra's already installed shared services instances/names
var environmentMap = { dev: 'dv', test: 'ts', staging: 'st', prod: 'pd' }

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    location: location
    resourceName: {
      applicationName: applicationName
      departmentCode: departmentCode
      environment: environmentMap[environment]
      sequenceNumber: sequenceNumber
    }
  }
}

// pulls in a databse of premra's already installed shared services instances/names
module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
  }
}

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
    keys: [
      {
        name: 'keyEncryptionKey'
        kty: 'RSA'
      }
    ]
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
        principalId: managedIdentity.outputs.principalId
        roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424') // Key Vault Crypto User
        principalType: 'ServicePrincipal'
      }
      {
        principalId: groupObjectId
        principalType: 'Group'
        // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-officer
        roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
      }
    ]
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneObj.id
            }
          ]
        }
        subnetResourceId: privateEndpointObj.subnetId
      }
    ]
  }
}

// module virtualNetwork 'br/public:avm/res/network/virtual-network:0.1.1' = {
//   name: '${uniqueString(deployment().name)}-vnet'
//   params: {
//     name: '${identifier}-vnet'
//     location: location
//     addressPrefixes: [
//       '10.0.0.0/16'
//     ]
//     subnets: [
//       {
//         addressPrefix: '10.0.1.0/24'
//         name: 'default'
//       }
//     ]
//   }
// }

// module privateDNSZone 'br/public:avm/res/network/private-dns-zone:0.2.3' = {
//   name: '$${identifier}-{uniqueString(deployment().name)}-pdnsz'
//   params: {
//     name: 'privatelink.vaultcore.azure.net'
//     location: 'global'
//     virtualNetworkLinks: [
//       {
//         registrationEnabled: false
//         virtualNetworkResourceId: virtualNetwork.outputs.resourceId
//       }
//     ]
//   }
// }

module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.1.2' = {
  name: '${uniqueString(deployment().name, location)}_MI'
  params: {
    name: '${toLower(identifier)}_MI'
    location: location
  }
}

// @description('The resource ID of the created Virtual Network Subnet.')
// output subnetResourceId string = virtualNetwork.outputs.subnetResourceIds[0]

@description('The principal ID of the created Managed Identity.')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

output managedIdentityPrincipalName string = managedIdentity.outputs.name

@description('The resource ID of the created Managed Identity.')
output managedIdentityResourceId string = managedIdentity.outputs.resourceId


@description('The resource ID of the created Private DNS Zone.')
output privateDNSZoneResourceId string = privateDnsZoneObj.id

output privateDNSZoneResourceName string = privateDnsZoneObj.name

@description('The resource ID of the created Key Vault.')
output keyVaultResourceId string = keyVault.outputs.resourceId
output keyVaultResourceName string = keyVault.outputs.name
