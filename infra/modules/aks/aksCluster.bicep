@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Kubernetes version')
param kubernetesVersion string

@description('Resource ID of the AKS subnet')
param aksSubnetId string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Resource ID of the user-assigned managed identity')
param userAssignedIdentityId string

@description('Enable private cluster')
param enablePrivateCluster bool

@description('System node pool VM count')
@minValue(1)
param systemNodeCount int

@description('System node pool VM size')
param systemNodeVmSize string

@description('User node pool VM count')
@minValue(1)
param userNodeCount int

@description('User node pool VM size')
param userNodeVmSize string

@description('System node pool autoscaler lower bound')
@minValue(1)
param systemNodeMinCount int

@description('System node pool autoscaler upper bound')
@minValue(1)
param systemNodeMaxCount int

@description('User node pool autoscaler lower bound')
@minValue(1)
param userNodeMinCount int

@description('User node pool autoscaler upper bound')
@minValue(1)
param userNodeMaxCount int

@description('Availability zones for agent pools (empty = regional)')
param availabilityZones array = []

@description('Authorized IP CIDR ranges for API server (public clusters only)')
param apiServerAuthorizedIPRanges array = []

@description('AKS SKU tier')
@allowed(['Free', 'Standard', 'Premium'])
param skuTier string = 'Standard'

@description('Control-plane auto-upgrade channel')
@allowed(['none', 'patch', 'stable', 'rapid', 'node-image'])
param upgradeChannel string = 'patch'

@description('Node OS auto-upgrade channel')
@allowed(['None', 'Unmanaged', 'SecurityPatch', 'NodeImage'])
param nodeOSUpgradeChannel string = 'NodeImage'

@description('Node OS disk type')
@allowed(['Ephemeral', 'Managed'])
param osDiskType string = 'Ephemeral'

@description('Node OS disk size in GB')
@minValue(30)
param osDiskSizeGB int = 30

@description('Max pods per node (AKS hard cap is 250 on Overlay; 110 is Azure default)')
@minValue(30)
@maxValue(250)
param maxPodsPerNode int = 50

@description('Azure AD admin group object IDs for cluster admin access')
param adminGroupObjectIds array

@description('DNS service IP address (must be within serviceCidr)')
param dnsServiceIP string = '10.0.0.10'

@description('Service CIDR for Kubernetes services')
param serviceCidr string = '10.0.0.0/16'

var aksName = 'aks-${customerName}-${environment}'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-10-01' = {
  name: aksName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: skuTier
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: 'aks-${customerName}-${environment}'
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: adminGroupObjectIds
    }
    apiServerAccessProfile: {
      enablePrivateCluster: enablePrivateCluster
      authorizedIPRanges: apiServerAuthorizedIPRanges
    }
    autoUpgradeProfile: {
      upgradeChannel: upgradeChannel
      nodeOSUpgradeChannel: nodeOSUpgradeChannel
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      outboundType: 'userAssignedNATGateway'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        osDiskType: osDiskType
        osDiskSizeGB: osDiskSizeGB
        maxPods: maxPodsPerNode
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: systemNodeMinCount
        maxCount: systemNodeMaxCount
        availabilityZones: availabilityZones
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
      {
        name: 'user'
        mode: 'User'
        count: userNodeCount
        vmSize: userNodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        osDiskType: osDiskType
        osDiskSizeGB: osDiskSizeGB
        maxPods: maxPodsPerNode
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: userNodeMinCount
        maxCount: userNodeMaxCount
        availabilityZones: availabilityZones
      }
    ]
    // Container Insights is still installed via the `omsagent` addon on the
    // 2025-10-01 API surface — the ARM schema does NOT accept
    // `azureMonitorProfile.containerInsights` (verified against docs + deploy
    // response: UnmarshalError on "unknown field containerInsights").
    // Despite the legacy name, `omsagent` on recent cluster versions is
    // wired to the AMA agent, not the old MMA. azureMonitorProfile.metrics
    // is kept for the managed Prometheus path.
    addonProfiles: union({
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurepolicy: {
        enabled: true
      }
    }, !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {})
    azureMonitorProfile: !empty(logAnalyticsWorkspaceId) ? {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    } : {}
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: union({
      workloadIdentity: {
        enabled: true
      }
      imageCleaner: {
        enabled: true
        intervalHours: 24
      }
    }, !empty(logAnalyticsWorkspaceId) ? {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        securityMonitoring: {
          enabled: true
        }
      }
    } : {})
    metricsProfile: {
      costAnalysis: {
        enabled: skuTier != 'Free'
      }
    }
    autoScalerProfile: {
      'balance-similar-node-groups': 'true'
      expander: 'least-waste'
      'max-graceful-termination-sec': '600'
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scan-interval': '10s'
    }
  }
}

resource maintenanceAutoUpgrade 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2025-10-01' = {
  parent: aksCluster
  name: 'aksManagedAutoUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Sunday'
        }
      }
      durationHours: 4
      startTime: '03:00'
      utcOffset: '+00:00'
    }
  }
}

resource maintenanceNodeOS 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2025-10-01' = {
  parent: aksCluster
  name: 'aksManagedNodeOSUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Saturday'
        }
      }
      durationHours: 4
      startTime: '03:00'
      utcOffset: '+00:00'
    }
  }
}

#disable-next-line use-recent-api-versions
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${aksName}-diag'
  scope: aksCluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output aksClusterId string = aksCluster.id
output aksClusterName string = aksCluster.name
output aksOidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
