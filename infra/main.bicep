targetScope = 'subscription'

import {
  environmentType
  tagsType
  networkConfigType
  aksConfigType
  featureFlagsType
  acrSkuType
  keyVaultSkuType
  roleAssignmentType
} from 'types.bicep'

// ============================================================================
// Parameters
// ============================================================================

@description('Customer name (short, lowercase, no special characters)')
param customerName string

@description('Environment name')
param environment environmentType

@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags tagsType

// Feature Flags
@description('Feature flags to enable or disable building blocks')
param features featureFlagsType

// Network
@description('Network configuration for VNet and subnets')
param networkConfig networkConfigType

// AKS
@description('AKS cluster configuration')
param aksConfig aksConfigType

@description('Azure AD admin group object IDs for AKS cluster admin access')
param adminGroupObjectIds array

// ACR
@description('ACR SKU')
param acrSku acrSkuType

// Key Vault
@description('Key Vault SKU')
param keyVaultSku keyVaultSkuType

// Monitoring
@description('Log Analytics retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int

// Extensibility
@description('Additional role assignments beyond the defaults')
param additionalRoleAssignments roleAssignmentType[] = []

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-${customerName}-${environment}-${location}'
var envTags = union(tags, {
  Environment: environment
  ManagedBy: 'Bicep'
})

// Well-known Azure role definition GUIDs
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: envTags
}

// ============================================================================
// Modules
// ============================================================================

module network 'modules/network/vnet.bicep' = {
  name: 'network-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
    vnetAddressPrefix: networkConfig.vnetAddressPrefix
    aksSubnetPrefix: networkConfig.aksSubnetPrefix
    servicesSubnetPrefix: networkConfig.servicesSubnetPrefix
    privateEndpointSubnetPrefix: networkConfig.privateEndpointSubnetPrefix
  }
}

module identity 'modules/identity/managedIdentity.bicep' = {
  name: 'identity-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
  }
}

module monitoring 'modules/monitoring/logAnalytics.bicep' = if (features.deployMonitoring) {
  name: 'monitoring-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
    retentionDays: logRetentionDays
  }
}

module acr 'modules/acr/containerRegistry.bicep' = if (features.deployAcr) {
  name: 'acr-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
    acrSku: acrSku
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    logAnalyticsWorkspaceId: features.deployMonitoring ? monitoring.outputs.workspaceId : ''
  }
}

module keyVault 'modules/keyvault/keyVault.bicep' = if (features.deployKeyVault) {
  name: 'keyvault-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
    skuName: keyVaultSku
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    logAnalyticsWorkspaceId: features.deployMonitoring ? monitoring.outputs.workspaceId : ''
    tenantId: tenant().tenantId
  }
}

module aks 'modules/aks/aksCluster.bicep' = {
  name: 'aks-deployment'
  scope: rg
  params: {
    location: location
    tags: envTags
    customerName: customerName
    environment: environment
    kubernetesVersion: aksConfig.kubernetesVersion
    aksSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: features.deployMonitoring ? monitoring.outputs.workspaceId : ''
    userAssignedIdentityId: identity.outputs.identityId
    enablePrivateCluster: aksConfig.enablePrivateCluster
    systemNodeCount: aksConfig.systemNodeCount
    systemNodeVmSize: aksConfig.systemNodeVmSize
    userNodeCount: aksConfig.userNodeCount
    userNodeVmSize: aksConfig.userNodeVmSize
    adminGroupObjectIds: adminGroupObjectIds
  }
}

// ============================================================================
// Role Assignments
// ============================================================================

// AKS kubelet identity -> ACR Pull (only when ACR is deployed)
module roleAcrPull 'modules/roleAssignment/roleAssignment.bicep' = if (features.deployAcr) {
  name: 'role-acr-pull'
  scope: rg
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId
    roleDefinitionId: acrPullRoleId
  }
}

// AKS managed identity -> Network Contributor on VNet
module roleNetworkContributor 'modules/roleAssignment/roleAssignment.bicep' = {
  name: 'role-network-contributor'
  scope: rg
  params: {
    principalId: identity.outputs.identityPrincipalId
    roleDefinitionId: networkContributorRoleId
  }
}

// AKS kubelet identity -> Key Vault Secrets User (only when Key Vault is deployed)
module roleKeyVaultSecretsUser 'modules/roleAssignment/roleAssignment.bicep' = if (features.deployKeyVault) {
  name: 'role-keyvault-secrets-user'
  scope: rg
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId
    roleDefinitionId: keyVaultSecretsUserRoleId
  }
}

// Additional role assignments (extensibility)
module extraRoles 'modules/roleAssignment/roleAssignment.bicep' = [
  for (role, i) in additionalRoleAssignments: {
    name: 'role-extra-${i}'
    scope: rg
    params: {
      principalId: role.principalId
      roleDefinitionId: role.roleDefinitionId
      principalType: role.?principalType ?? 'ServicePrincipal'
    }
  }
]

// ============================================================================
// Outputs
// ============================================================================

output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.aksClusterName
output aksOidcIssuerUrl string = aks.outputs.aksOidcIssuerUrl
output vnetId string = network.outputs.vnetId
output acrLoginServer string = features.deployAcr ? acr.outputs.acrLoginServer : ''
output keyVaultUri string = features.deployKeyVault ? keyVault.outputs.keyVaultUri : ''
output logAnalyticsWorkspaceId string = features.deployMonitoring ? monitoring.outputs.workspaceId : ''
