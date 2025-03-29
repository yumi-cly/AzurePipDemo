@description('The resource ID to which we are assigning the roles')
param resourceId string

param principalId string

param location string = resourceGroup().location

@description('''
(Optional). Should be seding the role assignments as below format.
{
  roleDefinitionIdOrName: 'Storage Blob Data Owner'
  principalId: userAssignedIdentity.outputs.principalId
  principalType: 'ServicePrincipal'
}
  (OR)
{
  roleDefinitionIdOrName: 'Storage Blob Data Owner'
  principalId: userAssignedIdentity.outputs.principalId
  principalType: 'ServicePrincipal'
  description: 'Assign Storage Blob Data Reader role to the managed identity on the storage account.'
}
''')
param roleAssignments roleAssignmentType

var builtInRoleNames = {
  // common
  Contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  Owner: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  Reader: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  'Role Based Access Control Administrator': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','f58310d9-a9f6-439a-9e8d-f62e7b41a168')
  'User Access Administrator': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  // keyvault
  'Key Vault Administrator': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','00482a5a-887f-4fb3-b363-3b7fe8e74483')
  'Key Vault Certificates Officer': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','a4417e6f-fecd-4de8-b567-7b0420556985')
  'Key Vault Certificate User': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
  'Key Vault Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','f25e0fa2-a7c8-4377-a976-54943a77a395')
  'Key Vault Crypto Officer': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','14b46e9e-c2b7-41b4-b07b-48a6ebf60603')
  'Key Vault Crypto Service Encryption User': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','e147488a-f6f5-4113-8e2d-b22465e65bf6')
  'Key Vault Crypto User': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','12338af0-0e69-4776-bea7-57ae8d297424')
  'Key Vault Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','21090545-7ca7-4776-b22c-e363652d74d2')
  'Key Vault Secrets Officer': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  'Key Vault Secrets User': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','4633458b-17de-408a-b874-0445c86b69e6')

  // storage
  'Reader and Data Access': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','c12c1c16-33a1-487b-954d-41c89c60f349')
  'Storage Account Backup Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1')
  'Storage Account Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','17d1049b-9a84-46fb-8f53-869881c3d3ab')
  'Storage Account Key Operator Service Role': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','81a9662b-bebf-436f-a333-f67b29880f12')
  'Storage Blob Data Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  'Storage Blob Data Owner': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  'Storage Blob Data Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  'Storage Blob Delegator': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','db58b8e5-c6ad-4a2a-8342-4190687cbf4a')
  'Storage File Data Privileged Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','69566ab7-960f-475b-8e7c-b3118f30c6bd')
  'Storage File Data Privileged Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','b8eda974-7b85-4f76-af95-65846b26df6d')
  'Storage File Data SMB Share Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb')
  'Storage File Data SMB Share Elevated Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','a7264617-510b-434b-a828-9731dc254ea7')
  'Storage File Data SMB Share Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','aba4ae5f-2193-4029-9191-0cb91df5e314')
  'Storage Queue Data Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  'Storage Queue Data Message Processor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','8a0f0c08-91a1-4084-bc3d-661d67233fed')
  'Storage Queue Data Message Sender': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','c6a89b2d-59bc-44d0-9896-0f6e12d7b80a')
  'Storage Queue Data Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','19e7f393-937e-4f77-808e-94535e297925')
  'Storage Table Data Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  'Storage Table Data Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions','76199698-9eea-4c19-bc75-cec21354c6b6')
}


var formattedRoleAssignments = [
  for (roleAssignment, index) in (roleAssignments ?? []): union(roleAssignment, {
    roleDefinitionId: builtInRoleNames[?roleAssignment.roleDefinitionIdOrName] ?? (contains(
        roleAssignment.roleDefinitionIdOrName,
        '/providers/Microsoft.Authorization/roleDefinitions/'
      )
      ? roleAssignment.roleDefinitionIdOrName
      : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionIdOrName))
  })
]

module resourceRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = [for(roleAssignment, index)  in (formattedRoleAssignments ?? []): {
  name: '${uniqueString(deployment().name, location)}-resourceRoleAssignmentDeployment_${index}'
  params: {
    // Required parameters
    principalId: principalId
    resourceId: resourceId
    roleDefinitionId: roleAssignment.roleDefinitionId
    // Non-required parameters
    description: roleAssignment.?description
    principalType: roleAssignment.principalType
    roleName: roleAssignment.roleDefinitionIdOrName
  }
}]


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
}[]?


// [for(roleAssignment, index)  in dbRoleAssignments: {

// module roleassignment 'br:pbcbicepprod.azurecr.io/'

// roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
// // Non-required parameters
// description: 'Assign Storage Blob Data Reader role to the managed identity on the storage account.'
// principalType: 'ServicePrincipal'
// roleName: 'Storage Blob Data Reader'
