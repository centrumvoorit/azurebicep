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
  kubernetesVersion: '1.35'
  systemNodeCount: 3
  systemNodeVmSize: 'Standard_D2s_v5'
  systemNodeMinCount: 3
  systemNodeMaxCount: 5
  userNodeCount: 3
  userNodeVmSize: 'Standard_D4s_v5'
  userNodeMinCount: 3
  userNodeMaxCount: 5
  enablePrivateCluster: false
  availabilityZones: []
  // OPGELET: leeg = API server bereikbaar vanaf heel internet.
  // Vul kantoor-/VPN-CIDR's in, bijv. ['203.0.113.0/24']
  apiServerAuthorizedIPRanges: []
  // Dev uses Free tier for cost; no SLA by design.
  skuTier: 'Free'
  upgradeChannel: 'patch'
  nodeOSUpgradeChannel: 'NodeImage'
  osDiskType: 'Ephemeral'
  osDiskSizeGB: 30
  maxPodsPerNode: 50
}

param adminGroupObjectIds = [
  // REQUIRED: vervang met Azure AD groep Object ID's. Combined with
  // disableLocalAccounts: true on the cluster, the all-zero placeholder
  // below causes a silent cluster lockout on deploy.
  '00000000-0000-0000-0000-000000000000'
]

// ACR - Standard voor dev (geen private endpoint nodig)
param acrSku = 'Standard'

// Key Vault
param keyVaultSku = 'standard'

// Monitoring
param logRetentionDays = 30
