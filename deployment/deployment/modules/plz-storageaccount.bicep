@description('Optional. Array of role assignments to create on the Key Vault.')
param keyVaultRoleAssignments array = []

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('''Optional. Network access configuration for the Key Vault. For security reasons, it is recommended to 
set the DefaultAction Deny. When undefined (e.g. {}), public access from all networks is enabled. Default value:

{
  defaultAction: \'Deny\'
  ipRules: []
  virtualNetworkRules: []
  bypass: \'AzureServices\'
}

NOTE: If not set and publicNetworkAccess is set to 'Enabled', a non-empty value for rsamNumberForPublicAccess must be defined.

Refer to the reference documentation here: 
https://docs.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults?pivots=deployment-language-bicep#networkruleset.
''')
param networkAcls object = {
  defaultAction: 'Deny'
  ipRules: []
  virtualNetworkRules: []
  bypass: 'AzureServices'
}

@description('''
Optional. Whether or not public network access is allowed for this resource. For security reasons it should be disabled. 
If set to \'\', it will be disabled by default if private endpoints are set and networkAcls are not set.

Note: If set to 'Enabled' and networkAcls are not set, a non-empty value for rsamNumberForPublicAccess must be defined.
''')
@allowed([
  ''
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Disabled'

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

@description('''Conditional. Required if both publicNetworkAccess is set to \'Enabled\' and networkAcls are empty which 
enables all public internet traffic.''')
param rsamNumberForPublicAccess string = ''

@description('Required. The id of the service principal that will be used to perform resource existence checks.')
param servicePrincipalId string

@description('Required. The service principal key for the related servicePrincipalId.')
@secure()
param servicePrincipalKey string

@description('Optional. File service and shares to deploy.')
param fileServices object = {}

@description('Optional. Queue service and queues to create.')
param queueServices object?

@description('Optional. Table service and tables to create.')
param tableServices object = {}

@description('Optional. Storage Account Sku Name. Default: Standard_ZRS')
@allowed(['Premium_LRS', 'Premium_ZRS', 'Standard_GRS', 'Standard_GZRS', 'Standard_LRS', 'Standard_RAGRS', 'Standard_RAGZRS', 'Standard_ZRS'])
param skuName string = 'Standard_ZRS'

@description('Optional. The role assignments to assign on the resource.')
param roleAssignments roleAssignmentType

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

var eventHubObj = first(filter(
  sharedResources.outputs.sharedSplunkEventHubObjs,
  x => x.resourceType == 'storageAccount'
))!
var blobPrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageBlob' )!)!, 
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
  'blob',
  location)
var queuePrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageQueue' )!)!,
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
 'queue',
 location)
var tablePrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageTable' )!)!,
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
  'table',
  location)
var filePrivateEndpoint = getPrivateEndpoint(
  first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'storageFile' )!)!,
  sharedResources.outputs.sharedPrivateEndpointObj.subnetId,
  'file',
  location)

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    resourceName: resourceName
    location: location
  }
}

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-getSharedResources'
  params: {
    location: location
  }
}

module nestedDependencies './utilities/bicep/dependencies.bicep' = {
  name: '${uniqueString(deployment().name, location)}-dependencies'
  params: {
    location: location
    resourceName: resourceName
    networkAcls: networkAcls
    publicNetworkAccess: publicNetworkAccess
    rsamNumberForPublicAccess: rsamNumberForPublicAccess
    roleAssignments: keyVaultRoleAssignments
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.13.3' = {
  name: '${uniqueString(deployment().name, location)}-storageAccount'
  params: {
    location: location
    name: resourceNames.outputs.resourceNames.st
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    queueServices: queueServices
    tableServices: tableServices
    fileServices: fileServices
    blobServices: {
      automaticSnapshotPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 10
      containerDeleteRetentionPolicyEnabled: true
      containers: [
        {
          enableNfsV3AllSquash: true
          enableNfsV3RootSquash: true
          name: 'default'
          publicAccess: 'None'
        }
      ]
      deleteRetentionPolicyDays: 9
      deleteRetentionPolicyEnabled: true
      diagnosticSettings: [
        {
          eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
          eventHubName: eventHubObj.name
        }
      ]
      lastAccessTimeTrackingPolicyEnabled: true
    }
    customerManagedKey: {
      keyName: nestedDependencies.outputs.customerManagedKeyName
      keyVaultResourceId: nestedDependencies.outputs.keyVaultResourceId
      userAssignedIdentityResourceId: nestedDependencies.outputs.managedIdentityResourceId
    }
    diagnosticSettings: [
      {
        eventHubAuthorizationRuleResourceId: eventHubObj.authorizationRuleId
        eventHubName: eventHubObj.name
      }
    ]
    enableHierarchicalNamespace: true
    enableNfsV3: true
    largeFileSharesState: 'Enabled'
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [ nestedDependencies.outputs.managedIdentityResourceId ]
    }
    privateEndpoints: concat([blobPrivateEndpoint], 
      !empty(queueServices) ? [queuePrivateEndpoint] : [],
      !empty(tableServices) ? [tablePrivateEndpoint] : [],
      !empty(fileServices) ? [filePrivateEndpoint] : [])
    requireInfrastructureEncryption: true
    roleAssignments: roleAssignments
    skuName: skuName
  }
}

@description('The name of the Storage Account.')
output name string = storageAccount.outputs.name

@description('The resource ID of the Storage Account.')
output resourceId string = storageAccount.outputs.resourceId

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = nestedDependencies.outputs.managedIdentityResourceId

@description('The resource id of the Key Vault.')
output keyVaultResourceId string = nestedDependencies.outputs.keyVaultResourceId

@description('The key name of the encryption key created with the Key Vault.')
output customerManagedKeyName string = nestedDependencies.outputs.customerManagedKeyName

type roleAssignmentType = {
  @description('Optional. The name (as GUID) of the role assignment. If not provided, a GUID will be generated.')
  name: string?

  @description('Required. The role to assign. You can provide either the display name of the role definition, the role definition GUID, or its fully qualified ID in the following format: \'/providers/Microsoft.Authorization/roleDefinitions/c2f4ef07-c644-48eb-af81-4b1b4947fb11\'.')
  roleDefinitionIdOrName: string

  @description('Required. The principal ID of the principal (user/group/identity) to assign the role to.')
  principalId: string

  @description('Optional. The principal type of the assigned principal ID.')
  principalType: ('ServicePrincipal' | 'Group' | 'User' | 'ForeignGroup' | 'Device')?

  @description('Optional. The description of the role assignment.')
  description: string?

  @description('Optional. The conditions on the role assignment. This limits the resources it can be assigned to. e.g.: @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:ContainerName] StringEqualsIgnoreCase "foo_storage_container".')
  condition: string?

  @description('Optional. Version of the condition.')
  conditionVersion: '2.0'?

  @description('Optional. The Resource Id of the delegated managed identity resource.')
  delegatedManagedIdentityResourceId: string?
}[]?
