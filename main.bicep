/* parameters */
// common parameters
@description('Specify the service name.')
param service string

@description('Specify the environment.')
param env string

@description('Specify Azure region.')
param region string = 'japaneast'

@description('Specify suffix the deployed name of the module. Default value is UTC time at the time the deployment is executed.')
param deploymentSuffix string = utcNow()

// resource group parameters
@description('Specify Principal ID to whom resource group role will be assignment.')
param principalId string

@description('Specify Principal Type of Principal ID.')
@allowed([
  'Device'
  'ForeignGroup'
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string

@description('Specify the RBAC role definition ID to be assigned to specified principal. Default value is `Storage Blob Data Contributor`.')
param storageRoleDefinitionId string = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// storage parameters
@description('Specify IP Address or CIDR list')
param allowIplist array

// key vault parameters
@description('Specify the RBAC role definition ID to be assigned to operator principal. Default value is ID of `Key Vault Crypto Officer` and `Key Vault Contributor`.')
param keyVaultOperatorRoleDefinitionIds array = [
  '00482a5a-887f-4fb3-b363-3b7fe8e74483'
  'f25e0fa2-a7c8-4377-a976-54943a77a395'
]

@description('Specify the RBAC role definition ID to be assigned to Storage Account. Default value is ID of `Key Vault Crypto Service Encryption User`')
param keyVaultStorageAccountRoleDefinitionId string = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

/* variables */
var resourceNamePrefix = '${toLower(service)}-${toLower(env)}'
var tagUsage = 'terraform_remote_state'

/* resource definitions */
targetScope = 'subscription'

//  resource group
resource tfstateRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${resourceNamePrefix}-tfstate'
  location: region
  tags: {
    Service: service
    Env: env
    Usage: tagUsage
  }
  managedBy: 'bicep'
  properties: {}
}

// User Assigned Managed Identity to assign Key Vault role to storage account for Service Side Encryption using Customer Managed Key
module tfstateUserAssignedManagedIdentity 'modules/userAssignedManagedId.bicep' = {
  scope: resourceGroup(tfstateRg.name)
  name: 'tfstate-mid-${deploymentSuffix}'

  params: {
    service: service
    env: env
    region: region
    tagUsage: tagUsage
  }
}

// Azure Key Vault for Storage Account Service Side Encryption.
module tfstateKeyVault 'modules/keyVault.bicep' = {
  scope: resourceGroup(tfstateRg.name)
  name: 'tfstate-key-vault-${deploymentSuffix}'

  params: {
    service: service
    env: env
    region: region
    tagUsage: tagUsage
    allowIplist: allowIplist
    operatorPrincipalId: principalId
    operatorPrincipalType: principalType
    operatorRoleDefinitionIds: keyVaultOperatorRoleDefinitionIds
    storageAccountPrincipalId: tfstateUserAssignedManagedIdentity.outputs.managedIdentity.principalId
    storageAccountRoleDefinitionId: keyVaultStorageAccountRoleDefinitionId
  }
}

// storage for terraform remote state
module tfstate_storage 'modules/storageAccount.bicep' = {
  scope: resourceGroup(tfstateRg.name)
  name: 'tfstate-storage-${deploymentSuffix}'

  params: {
    service: service
    env: env
    region: region
    tagUsage: tagUsage
    allowIplist: allowIplist
    principalId: principalId
    principalType: principalType
    roleDefinitionId: storageRoleDefinitionId
    managedIdentityPrincipalId: tfstateUserAssignedManagedIdentity.outputs.managedIdentity.id
    keyVaultUri: tfstateKeyVault.outputs.keyVaultUri
    keyVaultKeyName: tfstateKeyVault.outputs.keyVaultKeyName
  }
}
