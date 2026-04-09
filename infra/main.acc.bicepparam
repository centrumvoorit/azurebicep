using 'main.bicep'

param customerName = 'contoso'
param environment = 'acc'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Network
param vnetAddressPrefix = '10.2.0.0/16'
param aksSubnetPrefix = '10.2.0.0/20'
param servicesSubnetPrefix = '10.2.16.0/24'
param privateEndpointSubnetPrefix = '10.2.17.0/24'

// AKS
param aksKubernetesVersion = '1.30'
param aksSystemNodeCount = 2
param aksSystemNodeVmSize = 'Standard_D2s_v5'
param aksUserNodeCount = 2
param aksUserNodeVmSize = 'Standard_D4s_v5'
param enablePrivateCluster = true

param adminGroupObjectIds = [
  // Vervang met Azure AD groep Object ID's
  '00000000-0000-0000-0000-000000000000'
]

// ACR - Premium voor private endpoint
param acrSku = 'Premium'

// Key Vault
param keyVaultSku = 'standard'

// Monitoring
param logRetentionDays = 90
