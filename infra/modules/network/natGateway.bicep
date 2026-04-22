@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Number of outbound public IPs (each provides ~64k SNAT ports)')
@minValue(1)
@maxValue(16)
param outboundIpCount int = 1

@description('NAT gateway idle timeout in minutes')
@minValue(4)
@maxValue(120)
param idleTimeoutMinutes int = 4

var natGatewayName = 'natgw-${customerName}-${environment}'

resource publicIps 'Microsoft.Network/publicIPAddresses@2025-05-01' = [
  for i in range(0, outboundIpCount): {
    name: '${natGatewayName}-pip-${i}'
    location: location
    tags: tags
    sku: {
      name: 'Standard'
      tier: 'Regional'
    }
    zones: [
      '1'
      '2'
      '3'
    ]
    properties: {
      publicIPAllocationMethod: 'Static'
    }
  }
]

resource natGateway 'Microsoft.Network/natGateways@2025-05-01' = {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: idleTimeoutMinutes
    publicIpAddresses: [
      for i in range(0, outboundIpCount): {
        id: publicIps[i].id
      }
    ]
  }
}

output natGatewayId string = natGateway.id
