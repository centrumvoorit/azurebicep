@description('Principal ID to assign the role to')
param principalId string

@description('Role definition ID (GUID only, e.g., acdd72a7-3385-48ef-bd42-f606fba81ae7 for Reader)')
param roleDefinitionId string

@description('Principal type')
@allowed(['ServicePrincipal', 'Group', 'User'])
param principalType string = 'ServicePrincipal'

var roleAssignmentName = guid(principalId, roleDefinitionId, resourceGroup().id)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id
