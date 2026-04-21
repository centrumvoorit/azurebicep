@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param skuName string

@description('Resource ID of the private endpoint subnet')
param privateEndpointSubnetId string

@description('Resource ID of the VNet for DNS zone linking')
param vnetId string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Azure AD tenant ID')
param tenantId string

var keyVaultName = 'kv-${take(customerName, 6)}-${environment}-${take(uniqueString(resourceGroup().id), 8)}'

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${keyVaultName}-diag'
  scope: keyVault
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

module privateEndpoint '../privateEndpoint/privateEndpoint.bicep' = {
  name: '${keyVaultName}-pe'
  params: {
    location: location
    tags: tags
    name: 'pe-${keyVaultName}'
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: keyVault.id
    groupIds: ['vault']
    privateDnsZoneName: 'privatelink.vaultcore.azure.net'
    vnetId: vnetId
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
