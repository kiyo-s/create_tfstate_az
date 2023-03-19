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
param principalId string

@description('Specify Principal Type of Principal ID.')
param principalType string

@description('Specify the RBAC role definition ID to be assigned to specified principal. Default value is `Storage Blob Data Contributor`.')
param roleDefinitionId string

@description('Specify User Assigned Managed Identity Principal ID to be assigned to the Storage Account. Correct value is GUID format.')
param managedIdentityPrincipalId string

@description('Specify Azure Key Vault URI for SSE.')
param keyVaultUri string

@description('Specify Azure Key Vault Key name for SSE.')
param keyVaultKeyName string

// variables
var resourceNamePrefix = '${toLower(service)}${toLower(env)}'
var networkAclsIpRules = [for allowIp in allowIplist: {
  value: allowIp
}]

var roleAssignmentName = guid(resourceGroup().id, principalId, roleDefinitionId)

// resources
resource tfstateStorageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: '${resourceNamePrefix}tfstate'
  location: region
  tags: {
    Service: service
    Env: env
    Usage: tagUsage
  }
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityPrincipalId}': {}
      // reference
      // https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/logic-apps/create-managed-service-identity.md#create-user-assigned-identity-in-an-arm-template
    }
  }
  properties: {
    accessTier: 'Hot'

    // Security Settings
    /// authentication
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true

    /// storage encryption
    encryption: {
      identity: {
        userAssignedIdentity: managedIdentityPrincipalId
      }
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyvaulturi: keyVaultUri
        keyname: keyVaultKeyName
      }
      requireInfrastructureEncryption: true
    }

    /// traffic encryption
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'

    /// network security
    allowBlobPublicAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: networkAclsIpRules
    }
  }
}

resource tfstateBlob 'Microsoft.Storage/storageAccounts/blobServices@2022-05-01' = {
  name: 'default'
  parent: tfstateStorageAccount
  properties: {
    isVersioningEnabled: true
  }
}

resource tfstateBlobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
  name: 'tfstate'
  parent: tfstateBlob
  properties: {
    metadata: {
      Service: service
      Env: env
      Usage: tagUsage
    }
    publicAccess: 'None'
  }
}

// role assignment
resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: roleDefinitionId
}

resource tfstateRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: resourceGroup()
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinition.id
  }
}
