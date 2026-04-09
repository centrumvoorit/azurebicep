using 'main.bicep'

param customerName = 'contoso'
param environment = 'dev'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Network
param vnetAddressPrefix = '10.1.0.0/16'
param aksSubnetPrefix = '10.1.0.0/20'
param servicesSubnetPrefix = '10.1.16.0/24'
param privateEndpointSubnetPrefix = '10.1.17.0/24'

// AKS
param aksKubernetesVersion = '1.30'
param aksSystemNodeCount = 1
param aksSystemNodeVmSize = 'Standard_D2s_v5'
param aksUserNodeCount = 1
param aksUserNodeVmSize = 'Standard_D4s_v5'
param enablePrivateCluster = false

param adminGroupObjectIds = [
  // Vervang met Azure AD groep Object ID's
  '00000000-0000-0000-0000-000000000000'
]

// ACR - Standard voor dev (geen private endpoint nodig)
param acrSku = 'Standard'

// Key Vault
param keyVaultSku = 'standard'

// Monitoring
param logRetentionDays = 30
