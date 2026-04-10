using 'main.bicep'

param customerName = 'contoso'
param environment = 'dev'
param location = 'westeurope'

param tags = {
  CostCenter: 'IT'
  Owner: 'platform-team'
  Project: 'aks-platform'
}

// Feature Flags — schakel building blocks aan/uit
param features = {
  deployAcr: true
  deployKeyVault: true
  deployMonitoring: true
}

// Network
param networkConfig = {
  vnetAddressPrefix: '10.1.0.0/16'
  aksSubnetPrefix: '10.1.0.0/20'
  servicesSubnetPrefix: '10.1.16.0/24'
  privateEndpointSubnetPrefix: '10.1.17.0/24'
}

// AKS
param aksConfig = {
  kubernetesVersion: '1.30'
  systemNodeCount: 1
  systemNodeVmSize: 'Standard_D2s_v5'
  userNodeCount: 1
  userNodeVmSize: 'Standard_D4s_v5'
  enablePrivateCluster: false
}

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
