// AzureResourceManagerTemplateDeployment@3 does not yet support user-defined types in bicep. 
// See https://github.com/microsoft/azure-pipelines-tasks/issues/19942.
// When this functionality is available, the following can be utilized here:
// 
// import { 
//   roleAssignmentType
//   resourceNameType
//   networkAcl 
// } from './../../../utilities/bicep/common-types.bicep'

@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Required. Object representing segments of a PLZ-compliant resource name.')
param resourceName object

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

@description('''Conditional. Required if both publicNetworkAccess is set to \'Enabled\' and networkAcls are empty which 
enables all public internet traffic.''')
param rsamNumberForPublicAccess string = ''

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

@description('Required. The id of the service principal that will be used to perform resource existence checks.')
param servicePrincipalId string

@description('Required. The service principal key for the related servicePrincipalId.')
@secure()
param servicePrincipalKey string

@description('Optional. Array of role assignments to create on the Key Vault.')
param keyVaultRoleAssignments array = []

@description('Optional. All Key / Values to create. Requires local authentication to be enabled.')
param keyValues array = [
  {
    contentType: 'text'
    name: 'configKey1'
    value: 'configValue1'
  }
]

@description('''Optional. The customer managed key definition. Type definition:

type customerManagedKeyType = {
  @description('Required. The resource ID of a key vault to reference a customer managed key for encryption from.')
  keyVaultResourceId: string

  @description('Required. The name of the customer managed key to use for encryption.')
  keyName: string

  @description('Optional. The version of the customer managed key to reference for encryption. If not provided, using \'latest\'.')
  keyVersion: string?

  @description('Optional. User assigned identity to use when fetching the customer managed key. Required if no system assigned identity is available for use.')
  userAssignedIdentityResourceId: string?
}?
''')
param customerManagedKey object?

@description('''Optional. The managed identity definition for this resource. Type definition:

type managedIdentitiesType = {
  @description('Optional. Enables system assigned managed identity on the resource.')
  systemAssigned: bool?

  @description('Optional. The resource ID(s) to assign to the resource.')
  userAssignedResourceIds: string[]?
}?
''')
param managedIdentities object?

@description('Optional. The role assignments to assign on the resource.')
param roleAssignments roleAssignmentType

var diagEventHubAppConfig = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'appConfig'))!
var privateDnsZoneAppConfig = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'appConfig'))!

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: { resourceName: resourceName }
}

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-sharedResources'
  params: {
    location: location
  }
}

module nestedDependencies './dependencies.bicep' = if(empty(customerManagedKey) || empty(managedIdentities)) {
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

module appConfigAvm 'br/public:avm/res/app-configuration/configuration-store:0.2.3' = {
  name: '${uniqueString(deployment().name, location)}-appConfig'
  params: {
    name: resourceNames.outputs.resourceNames.appcs
    location: location
    createMode: 'Default'
    customerManagedKey: !empty(customerManagedKey) ? customerManagedKey : {
      keyName: nestedDependencies.outputs.customerManagedKeyName
      keyVaultResourceId: nestedDependencies.outputs.keyVaultResourceId
      userAssignedIdentityResourceId: managedIdentities.?userAssignedResourceIds[0] ?? nestedDependencies.outputs.managedIdentityResourceId
    }
    diagnosticSettings: [
      {
        name: '${resourceNames.outputs.resourceNames.appcs}-diag'
        eventHubAuthorizationRuleResourceId: diagEventHubAppConfig.authorizationRuleId
        eventHubName: diagEventHubAppConfig.name
        metricCategories: [{ category: 'AllMetrics' }]
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }, { categoryGroup: 'audit' }]
      }
    ]
    disableLocalAuth: false // required to add keyValues without ARM private endpoint enabled on the subscription
    enablePurgeProtection: true
    keyValues: keyValues
    managedIdentities: !empty(managedIdentities) ? managedIdentities :  {
      systemAssigned: false
      userAssignedResourceIds: [ nestedDependencies.outputs.managedIdentityResourceId ]
    }
    privateEndpoints: [
      {
        subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
        privateDnsZoneResourceIds: [privateDnsZoneAppConfig.id]
      }
    ]
    roleAssignments: roleAssignments
    publicNetworkAccess: 'Enabled' // required to add keyValues without ARM private endpoint enabled on the subscription
    softDeleteRetentionInDays: 1
  }
}

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
