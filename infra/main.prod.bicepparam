using 'main.bicep'

param customerName = 'contoso'
param environment = 'prod'
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
  vnetAddressPrefix: '10.3.0.0/16'
  aksSubnetPrefix: '10.3.0.0/20'
  servicesSubnetPrefix: '10.3.16.0/24'
  privateEndpointSubnetPrefix: '10.3.17.0/24'
}

// AKS
param aksConfig = {
  kubernetesVersion: '1.35'
  systemNodeCount: 3
  systemNodeVmSize: 'Standard_D4s_v5'
  userNodeCount: 3
  userNodeVmSize: 'Standard_D8s_v5'
  enablePrivateCluster: true
}

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
