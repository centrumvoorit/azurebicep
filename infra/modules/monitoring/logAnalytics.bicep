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
  }
}

output workspaceId string = logAnalytics.id
output workspaceCustomerId string = logAnalytics.properties.customerId
