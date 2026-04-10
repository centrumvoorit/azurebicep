@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string

@description('Resource ID of the private endpoint subnet')
param privateEndpointSubnetId string

@description('Resource ID of the VNet for DNS zone linking')
param vnetId string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

// ACR names cannot contain hyphens and must be globally unique
var acrName = 'acr${customerName}${environment}'

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: acrSku == 'Premium' ? 'Disabled' : 'Enabled'
    zoneRedundancy: acrSku == 'Premium' && environment == 'prod' ? 'Enabled' : 'Disabled'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${acrName}-diag'
  scope: acr
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

module privateEndpoint '../privateEndpoint/privateEndpoint.bicep' = if (acrSku == 'Premium') {
  name: '${acrName}-pe'
  params: {
    location: location
    tags: tags
    name: 'pe-${acrName}'
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: acr.id
    groupIds: ['registry']
    privateDnsZoneName: 'privatelink.azurecr.io'
    vnetId: vnetId
  }
}

output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
