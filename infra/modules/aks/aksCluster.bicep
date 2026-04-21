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

@description('Azure AD admin group object IDs for cluster admin access')
param adminGroupObjectIds array

@description('DNS service IP address (must be within serviceCidr)')
param dnsServiceIP string = '10.0.0.10'

@description('Service CIDR for Kubernetes services')
param serviceCidr string = '10.0.0.0/16'

var aksName = 'aks-${customerName}-${environment}'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksName
  location: location
  tags: tags
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
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      outboundType: 'loadBalancer'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osDiskSizeGB: 128
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: systemNodeCount
        maxCount: systemNodeCount + 2
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
        osDiskSizeGB: 128
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: userNodeCount
        maxCount: userNodeCount * 3
      }
    ]
    addonProfiles: !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {}
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    autoScalerProfile: {
      'balance-similar-node-groups': 'true'
      expander: 'random'
      'max-graceful-termination-sec': '600'
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scan-interval': '10s'
    }
  }
}

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
