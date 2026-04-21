@description('Azure region for all resources')
param location string

@description('Tags to apply to all resources')
param tags object

@description('Customer name used in resource naming')
param customerName string

@description('Environment name (dev, acc, prod)')
@allowed(['dev', 'acc', 'prod'])
param environment string

@description('Address prefix for the virtual network')
param vnetAddressPrefix string

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string

@description('Address prefix for the services subnet')
param servicesSubnetPrefix string

@description('Address prefix for the private endpoints subnet')
param privateEndpointSubnetPrefix string

var vnetName = 'vnet-${customerName}-${environment}'
var aksNsgName = 'nsg-aks-${customerName}-${environment}'
var servicesNsgName = 'nsg-services-${customerName}-${environment}'
var peNsgName = 'nsg-pe-${customerName}-${environment}'

// Outbound management-port deny rule reused across all three NSGs.
// Satisfies Azure.NSG.LateralTraversal — blocks SSH, RDP, and WinRM to any
// destination from the subnet, preventing east-west lateral traversal.
var denyLateralManagement = {
  name: 'DenyLateralManagement'
  properties: {
    priority: 200
    direction: 'Outbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRanges: [
      '22'
      '3389'
      '5985'
      '5986'
    ]
  }
}

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: aksNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      denyLateralManagement
    ]
  }
}

resource servicesNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: servicesNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      denyLateralManagement
    ]
  }
}

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: peNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      denyLateralManagement
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-aks'
        properties: {
          addressPrefix: aksSubnetPrefix
          networkSecurityGroup: {
            id: aksNsg.id
          }
        }
      }
      {
        name: 'snet-services'
        properties: {
          addressPrefix: servicesSubnetPrefix
          networkSecurityGroup: {
            id: servicesNsg.id
          }
        }
      }
      {
        name: 'snet-privateendpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksSubnetId string = vnet.properties.subnets[0].id
output servicesSubnetId string = vnet.properties.subnets[1].id
output privateEndpointSubnetId string = vnet.properties.subnets[2].id
