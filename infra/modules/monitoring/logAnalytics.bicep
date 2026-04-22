@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Log retention in days')
@minValue(30)
@maxValue(730)
param retentionDays int

@description('Daily ingestion cap in GB (-1 = unlimited). Set a cap on dev to avoid runaway costs.')
param dailyQuotaGb int = -1

var workspaceName = 'log-${customerName}-${environment}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    workspaceCapping: dailyQuotaGb > 0 ? {
      dailyQuotaGb: dailyQuotaGb
    } : null
    // Enable workspace replication to a secondary region for prod/acc (HA
    // requirement, satisfies Azure.Log.Replication). Dev stays single-region
    // to keep costs minimal.
    replication: environment == 'prod' || environment == 'acc' ? {
      enabled: true
      location: 'northeurope'
    } : null
  }
}

output workspaceId string = logAnalytics.id
output workspaceCustomerId string = logAnalytics.properties.customerId
