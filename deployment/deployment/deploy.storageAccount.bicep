@description('(Optional). The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location
 
@description('(Optional). The target environment. Default: dev')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Dev'
 
@minLength(1)
@maxLength(2) // controls resource name length violations
@description('(Optional). The sequence number to use in the resource naming. Default: 01')
param sequenceNumber string = '01'

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('(Optional). The application name (e.g. arc, polaris, etc.) to use in the resource naming.')
param applicationName string = 'CLM'
 
@minLength(1)
@maxLength(8) // controls resource name length violations
@description('(Optional). The department code (e.g. dah, ehps, cap, etc.) to use in the resource naming.')
param departmentCode string= 'MCA'
 
@description('(Required). The object id of the group to be given default permissions to the key vault through Azure portal.')
param groupObjectId string

@description('(Required). The resource group name in which all this is deployed.')
param resourceGroupName string

@description('(Conditional). the subnetID within vnet completely to which the network access will be granted.')
param funcAppVirtualNetworkSubnetId string?
 
var environmentMap = { dev: 'dv', staging: 'st', prod: 'pd' }
 

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

var blobPrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageBlob' )!)!, 
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
  'blob',
  location)

var tablePrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageTable' )!)!,
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
  'table',
  location)

var storageAccountEventHubObj = first(filter(
  sharedResources.outputs.sharedSplunkEventHubObjs,
  x => x.resourceType == 'storageAccount'
))!

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
 
module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
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
  }
}

 
//deploy with minimal config
module storageAccount 'br/public:avm/res/storage/storage-account:0.17.0' = {
  name: '${uniqueString(deployment().name, location)}-storageAccount'
  params: {
    // Required parameters
    name: resourceNames.outputs.resourceNames.st
    skuName: 'Standard_RAGZRS'
    kind: 'StorageV2'
    allowBlobPublicAccess: false
    location: location
    enableNfsV3: false
    enableSftp: false
    largeFileSharesState: 'Enabled'
    enableHierarchicalNamespace: false
    // defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Disabled'
    // allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    requireInfrastructureEncryption: true
    // supportsHttpsTrafficOnly: true
    // accessTier: 'Hot'
   
    networkAcls: {
        bypass: 'AzureServices'
        defaultAction: 'Deny'
        resourceAccessRules: []
        ipRules: []
        virtualNetworkRules: empty(funcAppVirtualNetworkSubnetId) ? [] : [
          {
            id: funcAppVirtualNetworkSubnetId
            action: 'Allow'
            state: 'Succeeded'
          }
        ]
    }
    
    tableServices: {
      tables: [
        {
          name: 'ActiveOperations'
        }
        {
          name: 'ArchivedOperations'
        }
      ]
      // diagnosticSettings: [
      //   {
      //   eventHubAuthorizationRuleResourceId: storageAccountEventHubObj.authorizationRuleId
      //   eventHubName: storageAccountEventHubObj.name
      //   }
      // ]
    }
    
    blobServices: {
      changeFeedEnabled: true
      restorePolicyEnabled: true
      restorePolicyDays: 7
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      deleteRetentionPolicyAllowPermanentDelete: false
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 8
      isVersioningEnabled: true
      // diagnosticSettings: [
      //   {
      //   eventHubAuthorizationRuleResourceId: storageAccountEventHubObj.authorizationRuleId
      //   eventHubName: storageAccountEventHubObj.name
      //   }
      // ]
    }

    fileServices: {
      // diagnosticSettings: [
      //   {
      //   eventHubAuthorizationRuleResourceId: storageAccountEventHubObj.authorizationRuleId
      //   eventHubName: storageAccountEventHubObj.name
      //   }
      // ]
    }

    queueServices: {
      // diagnosticSettings: [
      //   {
      //   eventHubAuthorizationRuleResourceId: storageAccountEventHubObj.authorizationRuleId
      //   eventHubName: storageAccountEventHubObj.name
      //   }
      // ]
    }

    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentity.outputs.resourceId
      ]
    }

    roleAssignments: [
       {
        principalId: userAssignedIdentity.outputs.principalId
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


    customerManagedKey: {
        //'${resourceNames.outputs.resourceNames.st}-cmk'
      keyName: 'keyEncryptionKey' 
      keyVaultResourceId: commonResources.outputs.keyVaultResourceId
      userAssignedIdentityResourceId: userAssignedIdentity.outputs.resourceId
    }

    diagnosticSettings: [
      {
        eventHubAuthorizationRuleResourceId: storageAccountEventHubObj.authorizationRuleId
        eventHubName: storageAccountEventHubObj.name
      }
    ]

    privateEndpoints: concat([blobPrivateEndpoint],[tablePrivateEndpoint]) 
  }
   dependsOn: [
    // storageAccountCmk
    // userAssignedIdentity
    // uaiKeyVaultRoleAssignment
  ]
}


@description('The resource ID of the created Azure storage account.')
output storageAccountResourceId string = storageAccount.outputs.resourceId
output storageAccountResourceName string = storageAccount.outputs.name
