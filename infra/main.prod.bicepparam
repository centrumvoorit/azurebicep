using 'main.bicep'

param customerName = 'contoso'
param environment = 'prod'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Network
param vnetAddressPrefix = '10.3.0.0/16'
param aksSubnetPrefix = '10.3.0.0/20'
param servicesSubnetPrefix = '10.3.16.0/24'
param privateEndpointSubnetPrefix = '10.3.17.0/24'

// AKS
param aksKubernetesVersion = '1.30'
param aksSystemNodeCount = 3
param aksSystemNodeVmSize = 'Standard_D4s_v5'
param aksUserNodeCount = 3
param aksUserNodeVmSize = 'Standard_D8s_v5'
param enablePrivateCluster = true

param adminGroupObjectIds = [
  // Vervang met Azure AD groep Object ID's
  '00000000-0000-0000-0000-000000000000'
]

// ACR - Premium met private endpoint en zone redundancy
param acrSku = 'Premium'

// Key Vault
param keyVaultSku = 'standard'

// Monitoring
param logRetentionDays = 365
