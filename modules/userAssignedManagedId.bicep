// parameters
@description('Specify the service name.')
param service string

@description('Specify the environment.')
param env string

@description('Specify Azure region.')
param region string = 'japaneast'

@description('Specify the value of `Usage` tag.')
param tagUsage string

// variables
var resourceName = '${toLower(service)}-${toLower(env)}'

// resources
resource userAssignManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${resourceName}-tfstate-sse'
  location: region
  tags: {
    Service: service
    Env: env
    Usage: tagUsage
    midUsage: 'storage_account_server_side_ecnryption'
  }
}

// outputs
output managedIdentity object = {
  id: userAssignManagedId.id
  principalId: userAssignManagedId.properties.principalId
}
