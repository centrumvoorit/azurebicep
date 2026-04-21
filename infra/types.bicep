// ============================================================================
// User-Defined Types for compile-time validation
// Fouten worden in de IDE gevangen, niet na een 20-minuten pipeline run.
// ============================================================================

@export()
@description('Deployment environment')
type environmentType = 'dev' | 'acc' | 'prod'

@export()
@description('Standard resource tags — extra tags zijn toegestaan')
type tagsType = {
  CostCenter: string
  Owner: string
  Project: string
  *: string
}

@export()
@description('Network configuration for VNet and subnets')
type networkConfigType = {
  @description('Address prefix for the virtual network (e.g., 10.1.0.0/16)')
  vnetAddressPrefix: string

  @description('Address prefix for the AKS subnet (e.g., 10.1.0.0/20)')
  aksSubnetPrefix: string

  @description('Address prefix for the services subnet (e.g., 10.1.16.0/24)')
  servicesSubnetPrefix: string

  @description('Address prefix for the private endpoints subnet (e.g., 10.1.17.0/24)')
  privateEndpointSubnetPrefix: string
}

@export()
@description('AKS cluster configuration')
type aksConfigType = {
  @description('Kubernetes version (e.g., 1.35)')
  kubernetesVersion: string

  @description('System node pool VM count (initial; within min/max when autoscaling)')
  systemNodeCount: int

  @description('System node pool VM size (e.g., Standard_D2s_v5)')
  systemNodeVmSize: string

  @description('System node pool autoscaler lower bound')
  systemNodeMinCount: int

  @description('System node pool autoscaler upper bound')
  systemNodeMaxCount: int

  @description('User node pool VM count (initial; within min/max when autoscaling)')
  userNodeCount: int

  @description('User node pool VM size (e.g., Standard_D4s_v5)')
  userNodeVmSize: string

  @description('User node pool autoscaler lower bound')
  userNodeMinCount: int

  @description('User node pool autoscaler upper bound')
  userNodeMaxCount: int

  @description('Enable private AKS cluster (recommended for acc/prod)')
  enablePrivateCluster: bool

  @description('Availability zones for agent pools (e.g., ["1","2","3"]). Empty array = regional placement.')
  availabilityZones: string[]

  @description('Authorized IP CIDR ranges for the API server (public clusters only). Empty array = allow all.')
  apiServerAuthorizedIPRanges: string[]

  @description('AKS SKU tier — Free (no SLA, dev only), Standard (uptime SLA), Premium (LTS)')
  skuTier: 'Free' | 'Standard' | 'Premium'

  @description('Control-plane auto-upgrade channel')
  upgradeChannel: 'none' | 'patch' | 'stable' | 'rapid' | 'node-image'

  @description('Node OS auto-upgrade channel')
  nodeOSUpgradeChannel: 'None' | 'Unmanaged' | 'SecurityPatch' | 'NodeImage'

  @description('Node OS disk type — Ephemeral (faster, cheaper, limited by VM cache size) or Managed')
  osDiskType: 'Ephemeral' | 'Managed'

  @description('Node OS disk size in GB')
  osDiskSizeGB: int

  @description('Max pods per node (PSRule.Azure.AKS.NodeMinPods wants >= 50 for efficient utilisation; 110 is AKS default with Overlay)')
  maxPodsPerNode: int

  @description('Number of managed outbound public IPs for NAT gateway (each provides ~64k SNAT ports)')
  natGatewayOutboundIpCount: int?

  @description('NAT gateway idle timeout in minutes (4–120)')
  natGatewayIdleTimeoutMinutes: int?
}

@export()
@description('Feature flags to enable or disable building blocks')
type featureFlagsType = {
  @description('Deploy Azure Container Registry')
  deployAcr: bool

  @description('Deploy Azure Key Vault')
  deployKeyVault: bool

  @description('Deploy Log Analytics and monitoring')
  deployMonitoring: bool
}

@export()
@description('ACR SKU tier')
type acrSkuType = 'Basic' | 'Standard' | 'Premium'

@export()
@description('Key Vault SKU tier')
type keyVaultSkuType = 'standard' | 'premium'

@export()
@description('Additional role assignment configuration')
type roleAssignmentType = {
  @description('Principal ID to assign the role to')
  principalId: string

  @description('Role definition ID (GUID)')
  roleDefinitionId: string

  @description('Principal type')
  principalType: 'ServicePrincipal' | 'Group' | 'User'?
}
