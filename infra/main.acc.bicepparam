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
  kubernetesVersion: '1.35'
  systemNodeCount: 3
  systemNodeVmSize: 'Standard_D2s_v5'
  systemNodeMinCount: 3
  systemNodeMaxCount: 5
  userNodeCount: 3
  userNodeVmSize: 'Standard_D4s_v5'
  userNodeMinCount: 3
  userNodeMaxCount: 8
  enablePrivateCluster: true
  availabilityZones: [
    '1'
    '2'
    '3'
  ]
  apiServerAuthorizedIPRanges: []
  skuTier: 'Standard'
  upgradeChannel: 'stable'
  nodeOSUpgradeChannel: 'NodeImage'
  osDiskType: 'Ephemeral'
  osDiskSizeGB: 30
  maxPodsPerNode: 50
  natGatewayOutboundIpCount: 2
}

param adminGroupObjectIds = [
  // REQUIRED: vervang met Azure AD groep Object ID's. Combined with
  // disableLocalAccounts: true on the cluster, the all-zero placeholder
  // below causes a silent cluster lockout on deploy.
  '00000000-0000-0000-0000-000000000000'
]

// ACR - Premium voor private endpoint
param acrSku = 'Premium'

// Key Vault
param keyVaultSku = 'standard'

// Monitoring
param logRetentionDays = 90
