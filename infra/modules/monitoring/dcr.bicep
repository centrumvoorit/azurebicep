@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Name of the AKS cluster (for DCR association)')
param aksClusterName string

var dcrName = 'dcr-${customerName}-${environment}-ci'

resource aksExisting 'Microsoft.ContainerService/managedClusters@2026-01-01' existing = {
  name: aksClusterName
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          streams: [
            'Microsoft-ContainerInsights-Group-Default'
          ]
          extensionName: 'ContainerInsights'
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Off'
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ContainerInsights-Group-Default'
        ]
        destinations: [
          'ciworkspace'
        ]
      }
    ]
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'ci-${customerName}-${environment}'
  scope: aksExisting
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'Container Insights DCR association. Removing this breaks log/metric collection.'
  }
}

output dcrId string = dcr.id
