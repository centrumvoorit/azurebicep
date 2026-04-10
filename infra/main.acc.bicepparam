using 'main.bicep'

param customerName = 'contoso'
param environment = 'acc'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Feature Flags
param features = {
  deployAcr: true
  deployKeyVault: true
  deployMonitoring: true
}

// Network
param networkConfig = {
  vnetAddressPrefix: '10.2.0.0/16'
  aksSubnetPrefix: '10.2.0.0/20'
  servicesSubnetPrefix: '10.2.16.0/24'
  privateEndpointSubnetPrefix: '10.2.17.0/24'
}

// AKS
param aksConfig = {
  kubernetesVersion: '1.30'
  systemNodeCount: 2
  systemNodeVmSize: 'Standard_D2s_v5'
  userNodeCount: 2
  userNodeVmSize: 'Standard_D4s_v5'
  enablePrivateCluster: true
}

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
