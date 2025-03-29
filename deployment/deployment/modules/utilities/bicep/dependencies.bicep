@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Required. Object representing segments of a PLZ-compliant resource name.')
param resourceName resourceNameType

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
param networkAcls networkAcl = {
  defaultAction: 'Deny'
  ipRules: []
  virtualNetworkRules: []
  bypass: 'AzureServices'
}

@description('Optional. The base time of the deployment.')
param baseTime string = utcNow()

@description('''
Optional. The epoch time integer value (in seconds) to use for the CMK expiry.

Note: Once the expiration value is set on a Key, this value CANNOT be modified and WILL result in a deployment failure
if it is changed. This deployment file uses a script to perform an existence check to determine if the key already exists. 
The key is only created if it does not already exist.
''')
param cmkExpiry int = dateTimeToEpoch(dateTimeAdd(baseTime, 'P1Y'))

@description('''
Required. The id of the service principal that will be used to perform on existing resource checks.
''')
param servicePrincipalId string

@description('''
Required. The service principal key for the related servicePrincipalId.
''')
@secure()
param servicePrincipalKey string

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType = []

@description('Optional. The resourceId of the user-assigned identity. If not provided, one is created.')
param userAssignedIdentityResourceId string?

var diagEventHubKeyVault = first(filter(sharedResources.outputs.sharedSplunkEventHubObjs, x => x.resourceType == 'keyVault'))!
var privateDnsZoneKeyVault = first(filter(sharedResources.outputs.sharedPrivateDnsZoneObjs, x => x.resourceType == 'keyVault'))!
var cmkName = '${resourceNames.outputs.resourceNames.kv}-cmk'
var resourceGroupNameSplitIndex = 4 // the position of the resource group name in a split resourceId

module resourceNames 'br:pbcbicepprod.azurecr.io/ecp/resource-name:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-resourceNames'
  params: {
    resourceName: resourceName
    location: location
  }
}

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-sharedResources'
  params: {
    location: location
  }
}

module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: '${uniqueString(deployment().name, location)}-umi'
  scope: resourceGroup(empty(userAssignedIdentityResourceId) ? resourceGroup().name : split(userAssignedIdentityResourceId!, '/')[resourceGroupNameSplitIndex])
  params: {
    name: empty(userAssignedIdentityResourceId) ? resourceNames.outputs.resourceNames.id : last(split(userAssignedIdentityResourceId!, '/'))
    location: location
  }
}

module keyVaultKeyExists 'get-key-vault-key.bicep' = {
  name: '${uniqueString(deployment().name, location)}-keyVaultKeyExistCheck'
  params: {
    location: location
    keyName: cmkName
    keyVaultName: resourceNames.outputs.resourceNames.kv
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.11.1' = {
  name: '${uniqueString(deployment().name, location)}-keyVault'
  params: {
    name: resourceNames.outputs.resourceNames.kv
    location: location
    diagnosticSettings: [
      {
        name: '${resourceNames.outputs.resourceNames.kv}-diag'
        eventHubAuthorizationRuleResourceId: diagEventHubKeyVault.authorizationRuleId
        eventHubName: diagEventHubKeyVault.name
        metricCategories: [{ category: 'AllMetrics', enabled: true }]
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs', enabled: true }, { categoryGroup: 'audit', enabled: true }]
      }
    ]
    enablePurgeProtection: true
    enableRbacAuthorization: true
    keys: keyVaultKeyExists.outputs.keyExists ? [] : [{
      #disable-next-line BCP037 // AVM issue - expects attributesEnabled
      attributesEnabled: true
      #disable-next-line BCP037 // AVM issue - expects attributesExp
      attributesExp: cmkExpiry
      attributes: {
        enabled: true
        exp: cmkExpiry
      }
      kty: 'RSA'
      keySize: 3072
      name: cmkName
      rotationPolicy: {
        attributes: {
          expiryTime: 'P1Y'
        }
        lifetimeActions: [
          {
            action: { type: 'Rotate' }
            trigger: { timeBeforeExpiry: 'P2M' }
          }
          {
            action: { type: 'Notify' }
            trigger: { timeBeforeExpiry: 'P30D' }
          }
        ]
      }
    }]
    networkAcls: networkAcls
    publicNetworkAccess: publicNetworkAccess
    privateEndpoints: [
      {
        location: location
        subnetResourceId: sharedResources.outputs.sharedPrivateEndpointObj.subnetId
        privateDnsZoneGroup: { privateDnsZoneGroupConfigs: [{ privateDnsZoneResourceId: privateDnsZoneKeyVault.id }] }
      }
    ]
    roleAssignments: union(roleAssignments, [{
        principalId: userAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Crypto Service Encryption User'
        principalType: 'ServicePrincipal'
      }]
    )
    softDeleteRetentionInDays: 7
    tags: ((networkAcls == null && publicNetworkAccess == 'Enabled') || !empty(rsamNumberForPublicAccess))
      ? union({ RsamNumberForPublicAccess: rsamNumberForPublicAccess }, resourceGroup().tags)
      : resourceGroup().tags
  }
}

module getKvKey './get-key-vault-key.bicep' = {
  name: '${uniqueString(deployment().name, location)}-getKeyVaultKey'
  params: {
    location: location
    keyName: cmkName
    keyVaultName: keyVault.outputs.name
    servicePrincipalId: servicePrincipalId
    servicePrincipalKey: servicePrincipalKey
  }
}

@description('''The fully-qualified url of the key vault key, including the version.

Also known as:
- `cmkUriWithVersion`
- `keyUriWithVersion`

example:

`https://yourkv00.vau1t.azure.net/keys/your-key-name/your-key-version` ''')
output keyVaultKeyUriWithVersion string = getKvKey.outputs.keyUriWithVersion

@description('The uri of the Key Vault Key.')
output keyVaultKeyUri string = getKvKey.outputs.keyUri

@description('The resource id of the managed identity.')
output managedIdentityResourceId string = userAssignedIdentity.outputs.resourceId

@description('The principal id of the managed identity.')
output managedIdentityPrincipalId string = userAssignedIdentity.outputs.principalId

@description('The client id of the managed identity.')
output managedIdentityClientId string = userAssignedIdentity.outputs.clientId

@description('The name of the Key Vault.')
output keyVaultName string = keyVault.outputs.name

@description('The resource id of the Key Vault.')
output keyVaultResourceId string = keyVault.outputs.resourceId

@description('The key name of the encryption key created with the Key Vault.')
output customerManagedKeyName string = cmkName

@description('Object representing a role assignment.')
type roleAssignmentType = {
  @description('The ID or name of the role definition.')
  roleDefinitionIdOrName: string
  @description('The ID of the principal.')
  principalId: string
  @description('The type of the principal.')
  principalType: 'Device' | 'ForeignGroup' | 'Group' | 'ServicePrincipal' | 'User' | null
  @description('Optional. The description of the role assignment.')
  description: string?
  @description('Optional the condition.')
  condition: string?
  @description('The condition version.')
  conditionVersion: '2.0' | null
  @description('Optional. The resource ID of the delegated identity.')
  delegatedManagedIdentityResourceId: string?
}[]

@description('Object representing segments of a PLZ-compliant resource name.')
type resourceNameType = {
  @description('Required. The application name (e.g. arc, polaris, etc.).')
  @minLength(1)
  @maxLength(8) // controls resource name length violations
  applicationName: string
  @description('Required. The department code (e.g. dah, ehps, cap, etc.).')
  @minLength(1)
  @maxLength(8) // controls resource name length violations
  departmentCode: string
  @description('Optional. The location where resources are deployed.')
  location: string?
  @description('Required. The sequence number.')
  @minLength(1)
  @maxLength(2) // controls resource name length violations
  sequenceNumber: string
  @description('Required. The target environment (dev, test, staging, prod, nonprod, etc.).')
  @minLength(1)
  @maxLength(7) // controls resource name length violations
  environment: string
}

@description('Rules governing the accessibility of the resource from specific network locations.')
type networkAcl = {
  @description('''Required. The default action when no rule from ipRules and from virtualNetworkRules match. 
  This is only used after the bypass property has been evaluated.''')
  defaultAction: 'Allowed' | 'Deny'
  @description('Required. The array of strings representing the IP address rules. If no IP rules, set to an empty array \'[]\'.')
  ipRules: string[]
  @description('Required. The list of virtual network rules. If no vnet rules, set to an empty array \'[]\'')
  virtualNetworkRules: {
    @description('Required. The ID of the virtual network rule.')
    id: string
    @description('Property to specify whether NRP will ignore the check if parent subnet has serviceEndpoints configured.')
    ignoreMissingVnetServiceEndpoint: bool
  }[]
  @description('Optional. Defines what traffic can bypass network rules.')
  bypass: 'AzureServices' | 'None'
}
