// parameters
@description('Specify the service name.')
param service string

@description('Specify the environment.')
param env string

@description('Specify Azure region.')
param region string = 'japaneast'

@description('Specify the value of `Usage` tag.')
param tagUsage string

@description('Specify IP Address or CIDR list.')
param allowIplist array

@description('Specify Principal ID to whom resource group role will be assignment.')
param operatorPrincipalId string

@description('Specify Principal Type of Principal ID.')
param operatorPrincipalType string

@description('Specify the RBAC role definition ID to be assigned to operator principal.')
param operatorRoleDefinitionIds array

@description('Specify the principal ID of the Storage Account to be encrypted.')
param storageAccountPrincipalId string

@description('Specify the RBAC role definition ID to be assigned to Storage Account.')
param storageAccountRoleDefinitionId string

// variables
var resourceName = '${toLower(service)}-${toLower(env)}'
var networkAclsIpRules = [for allowIp in allowIplist: {
  value: allowIp
}]
var operatorRoleAssignNames = [for operatorRoleDefinitionId in operatorRoleDefinitionIds: guid(
  resourceGroup().id, operatorPrincipalId, operatorRoleDefinitionId
)]
var storageAccountRoleAssignName = guid(resourceGroup().id, storageAccountPrincipalId, storageAccountRoleDefinitionId)

// resources
/// Azure Key Vault
resource tfstateKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: resourceName
  location: region
  tags: {
    Service: service
    Env: env
    Usage: tagUsage
  }
  properties: {
    createMode: 'default'
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: networkAclsIpRules
    }
    sku: {
      name: 'standard'
      family: 'A'
    }
    softDeleteRetentionInDays: 7
    tenantId: tenant().tenantId
  }
}

/// Role Assignment
resource operatorRoleDefinitions 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = [for operatorRoleDefinitionId in operatorRoleDefinitionIds: {
  scope: subscription()
  name: operatorRoleDefinitionId
}]

resource tfstateKeyVaultOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (operatorRoleAssignName, i) in operatorRoleAssignNames: {
  name: operatorRoleAssignName
  scope: resourceGroup()
  properties: {
    principalId: operatorPrincipalId
    principalType: operatorPrincipalType
    roleDefinitionId: operatorRoleDefinitions[i].id
  }
}]

resource storageAccountRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: storageAccountRoleDefinitionId
}

resource tfstateKeyVaultStorageAccountRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: storageAccountRoleAssignName
  scope: resourceGroup()
  properties: {
    principalId: storageAccountPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageAccountRoleDefinition.id
  }
}

/// Azure Key Vault Key for encryption Storage Account
resource tfstateKeyVaultKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = {
  name: 'sse-key'
  dependsOn: [
    tfstateKeyVaultOperatorRoleAssignment
  ]
  tags: {
    Service: service
    Env: env
    Usage: tagUsage
    keyUsage: 'storage_account_server_side_encryption'
  }
  parent: tfstateKeyVault
  properties: {
    attributes: {
      enabled: true
    }
    keySize: 4096
    kty: 'RSA'
    rotationPolicy: {
      attributes: {
        expiryTime: 'P28D'
      }
      lifetimeActions: [
        {
          action: {
            type: 'rotate'
          }
          trigger: {
            timeBeforeExpiry: 'P7D'
          }
        }
      ]
    }
  }
}

// outputs
output keyVaultUri string = tfstateKeyVault.properties.vaultUri
output keyVaultKeyName string = tfstateKeyVaultKey.name
