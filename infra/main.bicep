targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Customer name (short, lowercase, no special characters)')
param customerName string

@description('Environment name')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

// Network
@description('Address prefix for the virtual network')
param vnetAddressPrefix string

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string

@description('Address prefix for the services subnet')
param servicesSubnetPrefix string

@description('Address prefix for the private endpoints subnet')
param privateEndpointSubnetPrefix string

// AKS
@description('Kubernetes version')
param aksKubernetesVersion string

@description('System node pool VM count')
param aksSystemNodeCount int

@description('System node pool VM size')
param aksSystemNodeVmSize string

@description('User node pool VM count')
param aksUserNodeCount int

@description('User node pool VM size')
param aksUserNodeVmSize string

@description('Enable private AKS cluster')
param enablePrivateCluster bool

@description('Azure AD admin group object IDs for AKS cluster admin access')
param adminGroupObjectIds array

// ACR
@description('ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string

// Key Vault
@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string

// Monitoring
@description('Log Analytics retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int

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

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
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
    vnetAddressPrefix: vnetAddressPrefix
    aksSubnetPrefix: aksSubnetPrefix
    servicesSubnetPrefix: servicesSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
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

module monitoring 'modules/monitoring/logAnalytics.bicep' = {
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

module acr 'modules/acr/containerRegistry.bicep' = {
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
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module keyVault 'modules/keyvault/keyVault.bicep' = {
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
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
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
    kubernetesVersion: aksKubernetesVersion
    aksSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    userAssignedIdentityId: identity.outputs.identityId
    enablePrivateCluster: enablePrivateCluster
    systemNodeCount: aksSystemNodeCount
    systemNodeVmSize: aksSystemNodeVmSize
    userNodeCount: aksUserNodeCount
    userNodeVmSize: aksUserNodeVmSize
    adminGroupObjectIds: adminGroupObjectIds
  }
}

// ============================================================================
// Role Assignments
// ============================================================================

// AKS kubelet identity -> ACR Pull
module roleAcrPull 'modules/roleAssignment/roleAssignment.bicep' = {
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

// AKS kubelet identity -> Key Vault Secrets User
module roleKeyVaultSecretsUser 'modules/roleAssignment/roleAssignment.bicep' = {
  name: 'role-keyvault-secrets-user'
  scope: rg
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId
    roleDefinitionId: keyVaultSecretsUserRoleId
  }
}

// ============================================================================
// Outputs
// ============================================================================

output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.aksClusterName
output acrLoginServer string = acr.outputs.acrLoginServer
output keyVaultUri string = keyVault.outputs.keyVaultUri
