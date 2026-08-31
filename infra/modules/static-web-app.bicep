@description('Static Web App resource name.')
param name string

@description('Supported Azure Static Web Apps location.')
param location string

@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

param tags object = {}

resource app 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
  }
}

output id string = app.id
output name string = app.name
output defaultHostname string = app.properties.defaultHostname
