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

@description('Required. The id of the service principal')
param servicePrincipalId string

@description('Required. The service principal key')
@secure()
param servicePrincipalKey string

@maxLength(24)
@description('Optional. Unique identifier for the deployment. Will appear in resource names. Must be 24 characters or less.')
param identifier string

@description('The Azure AD id of a group to grant privileged key vault roles to.')
param groupObjectId string


// @description('Required. The id of the service principal.')
// param servicePrincipalId string
 
// @description('Required. The service principal key.')
// @secure()
// param servicePrincipalKey string
 

output sequenceNumber_var string = sequenceNumber
output departmentCode_var string = departmentCode
output applicationName_var string = applicationName

output location_var string = location
output identifier_var string = identifier
output groupObjectId_param string = groupObjectId
//output resourceName_param object = resourceName

var diagEventHubKeyVault = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'keyVault'))!
var privateDnsZoneObjKeyVault = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'keyVault'))!
var privateEndpointObj = sharedResources.outputs.sharedPrivateEndpointObj
var logAnalyticsWorkspaceObj = sharedResources.outputs.sharedLogAnalyticsWorkspaceObj
var logAnalyticsWorkspaceId = resourceId(logAnalyticsWorkspaceObj.subscriptionId, logAnalyticsWorkspaceObj.resourceGroupName, 'Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspaceObj.workspaceName)

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
              privateDnsZoneResourceId: privateDnsZoneObjKeyVault.id
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

module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: '${uniqueString(deployment().name, location)}_UMI'
  params: {
    name:  resourceNames.outputs.resourceNames.id
    location: location
  }
}

func getPrivateEndpoint(sharedPrivateDnsZoneObj object, subnetResourceId string, service string, location string) object => {
  privateDnsZoneGroup: {
    privateDnsZoneGroupConfigs: [ {
      privateDnsZoneResourceId: sharedPrivateDnsZoneObj.id
    } ]
  }
  location: location
  service: service
  subnetResourceId: subnetResourceId
  enableTelemetry: false
}

var queueServices =       {
   queues: [
          {
            metadata: {}
            name: 'inputmessages'
          }
          {
            metadata: {}
            name: 'inprocessmessages'
          }
          {
            metadata: {}
            name: 'failedmessages'
          }
        ]}

var tableServices = {
  tableServices: {
      tables: [
        {
          name: 'ActiveOperations'
        }
        {
          name: 'ArchivedOperations'
        }
      ]
    }
}
// var eventHubObj = first(filter(
//   sharedResources.outputs.sharedSplunkEventHubObjs,
//   x => x.resourceType == 'storageAccount'
// ))!
// var blobPrivateEndpoint = getPrivateEndpoint(
//   first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageBlob' )!)!, 
//   sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
//   'blob',
//   location)
// var queuePrivateEndpoint = getPrivateEndpoint(
//   first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageQueue' )!)!,
//   sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
//  'queue',
//  location)
// var tablePrivateEndpoint = getPrivateEndpoint(
//   first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageTable' )!)!,
//   sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
//   'table',
//   location)
// var filePrivateEndpoint = getPrivateEndpoint(
//   first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageFile' )!)!,
//   sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
//   'file',
//   location)

// module storageAccount 'br/public:avm/res/storage/storage-account:0.13.3' = {
//   name: '${uniqueString(deployment().name, location)}-storageAccount'
//   params: {
//     location: location
//     name: resourceNames.outputs.resourceNames.st
//     allowBlobPublicAccess: false
//     allowSharedKeyAccess: false
//     queueServices: queueServices
//     tableServices: tableServices
//     // fileServices: fileServices
//     blobServices: {
//       automaticSnapshotPolicyEnabled: true
//       containerDeleteRetentionPolicyDays: 10
//       containerDeleteRetentionPolicyEnabled: true
//       containers: [
//         {
//           enableNfsV3AllSquash: true
//           enableNfsV3RootSquash: true
//           name: 'default'
//           publicAccess: 'None'
//         }
//       ]
//       deleteRetentionPolicyDays: 9
//       deleteRetentionPolicyEnabled: true
//       diagnosticSettings: [
//         {
//           eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
//           eventHubName: eventHubObj.name
//         }
//       ]
//       lastAccessTimeTrackingPolicyEnabled: true
//     }
//     customerManagedKey: {
//       keyName: 'keyEncryptionKey'
//       keyVaultResourceId: keyVault.outputs.resourceId
//       userAssignedIdentityResourceId: managedIdentity.outputs.resourceId
//     }
//     diagnosticSettings: [
//       {
//         eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
//         eventHubName: eventHubObj.name
//       }
//     ]
//     enableHierarchicalNamespace: true
//     enableNfsV3: true
//     largeFileSharesState: 'Enabled'
//     managedIdentities: {
//       systemAssigned: false
//       userAssignedResourceIds: [ managedIdentity.outputs.resourceId ]
//     }
//     privateEndpoints: concat([blobPrivateEndpoint], 
//       !empty(queueServices) ? [queuePrivateEndpoint] : [],
//       !empty(tableServices) ? [tablePrivateEndpoint] : [],
//       []
//       // !empty(fileServices) ? [filePrivateEndpoint] : []
//       )
//     requireInfrastructureEncryption: true
//     roleAssignments: [
//       {
//         principalId: groupObjectId
//         principalType: 'Group'
//         roleDefinitionIdOrName: 'Storage Account Contributor'
//       }
//       {
//         principalId: groupObjectId
//         principalType: 'Group'
//         roleDefinitionIdOrName: 'Storage Blob Data Owner'
//       }
//     ]
//     skuName: 'Standard_LRS'
//   }
// }

//var diagEventHubStorage = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'storageAccount'))!
// var eventHubObj = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'storageAccount'))!
// var privateDnsZoneObjStorage = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageBlob')!)!

module azureStorageAccount 'br/public:avm/res/storage/storage-account:0.17.4' = {
  name: '${uniqueString(deployment().name, location)}_Storage'
  params: {
    location: location
    name: resourceNames.outputs.resourceNames.st
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    // TODO
    //allowBlobPublicAccess: false
    
    enableNfsV3: false
    enableSftp: false
    enableHierarchicalNamespace: false
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Disabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false

    // TODO
    // networkAcls: {
    //   bypass: 'AzureServices'
    //   defaultAction: 'Deny'
    //   resourceAccessRules: []
    // }
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'

    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        managedIdentity.outputs.resourceId
      ]
    }
    // TODO
    // privateEndpoints: [
    //   {
    //     service: 'blob'
    //     location: location
    //     subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
    //     privateDnsZoneGroup: { privateDnsZoneGroupConfigs: [{ privateDnsZoneResourceId: privateDnsZoneObjStorage.id }] }
    //   }
    // ]
    // privateEndpoints: [
    //   {
    //     privateDnsZoneGroup: {
    //       privateDnsZoneGroupConfigs: [
    //         {
    //           privateDnsZoneResourceId: privateDnsZoneObjStorage.id
    //         }
    //       ]
    //     }
    //     location: location
    //     service: 'blob'
    //     subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
    //     tags: resourceGroup().tags
    //     enableTelemetry: false
    //   }
    // ]
    queueServices: {
      // TODO
      // diagnosticSettings: [
      //   {
      //     name: '${resourceNames.outputs.resourceNames.st}-QueueDiag'
      //     workspaceResourceId: logAnalyticsWorkspaceId
      //     // eventHubAuthorizationRuleResourceId: diagEventHubStorage.authorizationRuleId
      //     // eventHubName: diagEventHubStorage.name
      //     metricCategories: [{ category: 'AllMetrics', enabled: true }]
      //     logCategoriesAndGroups: [{ categoryGroup: 'allLogs', enabled: true }, { categoryGroup: 'audit', enabled: true }]
      //   }
        
      // ]
      queues: [
        {
          metadata: {}
          name: 'inputmessages'
        }
        {
          metadata: {}
          name: 'inprocessmessages'
        }
        {
          metadata: {}
          name: 'failedmessages'
        }
      ]
    }
    tableServices: {
      // TODO
      // diagnosticSettings: [
      //   {
      //     name: '${resourceNames.outputs.resourceNames.st}-TableDiag'
      //      workspaceResourceId: logAnalyticsWorkspaceId
      //     // eventHubAuthorizationRuleResourceId: diagEventHubStorage.authorizationRuleId
      //     // eventHubName: diagEventHubStorage.name
      //     metricCategories: [{ category: 'AllMetrics', enabled: true }]
      //     logCategoriesAndGroups: [{ categoryGroup: 'allLogs', enabled: true }, { categoryGroup: 'audit', enabled: true }]
      //   }
      // ]
      tables: [
        {
          name: 'ActiveOperations'
        }
        {
          name: 'ArchivedOperations'
        }
      ]
    }
    blobServices: {
      
      allowBlobPublicAccess: false
      automaticSnapshotPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 10
      containerDeleteRetentionPolicyEnabled: true
      containers: [
        {
          name: '${identifier}container'
          publicAccess: 'None'
        }
      ]
      deleteRetentionPolicyDays: 9
      deleteRetentionPolicyEnabled: true
      // TODO
      // diagnosticSettings: [
      //   {
      //     name: '${resourceNames.outputs.resourceNames.st}-BlobDiag'
      //     workspaceResourceId: logAnalyticsWorkspaceId
      //     // eventHubAuthorizationRuleResourceId: diagEventHubStorage.authorizationRuleId
      //     // eventHubName: diagEventHubStorage.name
      //     metricCategories: [{ category: 'AllMetrics', enabled: true }]
      //     logCategoriesAndGroups: [{ categoryGroup: 'allLogs', enabled: true }, { categoryGroup: 'audit', enabled: true }]
      //   }
      // ]
      // diagnosticSettings: [
      //   {
      //     eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
      //     eventHubName: eventHubObj.name
      //   }
      // ]
      lastAccessTimeTrackingPolicyEnabled: true
    } 
    // TODO
    // customerManagedKey: {
    //   keyName: 'keyEncryptionKey'
    //   keyVaultResourceId: keyVault.outputs.resourceId
    //   userAssignedIdentityResourceId: managedIdentity.outputs.resourceId
    // }

    roleAssignments: [
      // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-account-contributor
      { principalId: groupObjectId, roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab', principalType:'Group' }
      // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
      { principalId: groupObjectId, roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe', principalType:'Group' }
    ]
  }
}

// module appInsightInstance 'br/public:avm/res/insights/component:0.6.0' = {
//   name: '${uniqueString(deployment().name, location)}_AppInsights'
  
//     params: {
//       location: location
//       name: resourceNames.outputs.resourceNames.appi
//       enableTelemetry: false
//       applicationType: 'web'
//       kind: 'web'
//       workspaceResourceId: logAnalyticsWorkspaceId      
  
//     // TODO
//     // Non-required parameters
//     // diagnosticSettings: [
//     //   {
//     //     eventHubAuthorizationRuleResourceId: '<eventHubAuthorizationRuleResourceId>'
//     //     eventHubName: '<eventHubName>'
//     //     metricCategories: [
//     //       {
//     //         category: 'AllMetrics'
//     //       }
//     //     ]
//     //     name: 'customSetting'
//     //     storageAccountResourceId: '<storageAccountResourceId>'
//     //     workspaceResourceId: '<workspaceResourceId>'
//     //   }
//     // ]
  
//     tags: {
//       Environment: 'Non-Prod'
//       'hidden-title': 'Appinsight instance for MCA CLM'
//       Role: 'Telemetry'
//     }
//   }
// }

// module metricAlert './modules/plz-insight-health-check.bicep' = {
//   name: '${uniqueString(deployment().name, location)}-metricAlertDeployment'
//   params: {
//     name: '${resourceNames.outputs.resourceNames.func} | Health Check | Alert'
//     environment: environment
//     alertDescription: 'HealthCheck alert for the function app (${resourceNames.outputs.resourceNames.func})'
//     alertCriteriaType: 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
//     scopes: [  ]
//     targetResourceType: 'Microsoft.Web/sites'
//   }
// }

// @description('The resource ID of the created Virtual Network Subnet.')
// output subnetResourceId string = virtualNetwork.outputs.subnetResourceIds[0]

@description('The principal ID of the created Managed Identity.')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

output managedIdentityPrincipalName string = managedIdentity.outputs.name

@description('The resource ID of the created Managed Identity.')
output managedIdentityResourceId string = managedIdentity.outputs.resourceId


@description('The resource ID of the created Private DNS Zone for Keyvault.')
output privateKeyVaultDNSZoneResourceId string = privateDnsZoneObjKeyVault.id

output privateKeyVaultDNSZoneResourceName string = privateDnsZoneObjKeyVault.name

// @description('The resource ID of the created Private DNS Zone for Storage.')
// output privateStorageDNSZoneResourceId string = privateDnsZoneObjStorage.id

// output privateStorageDNSZoneResourceName string = privateDnsZoneObjStorage.name

@description('The resource ID of the created Key Vault.')
output keyVaultResourceId string = keyVault.outputs.resourceId
output keyVaultResourceName string = keyVault.outputs.name

@description('The resource ID of the created Azure storage account.')
output storageAccountResourceId string = azureStorageAccount.outputs.resourceId
output storageAccountResourceName string = azureStorageAccount.outputs.name

// @description('The resource ID of the app insight.')
// output appInsightResourceId string = appInsightInstance.outputs.resourceId
// output appInsightName string = appInsightInstance.outputs.name
