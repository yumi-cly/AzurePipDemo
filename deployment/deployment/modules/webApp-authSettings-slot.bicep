
@description('Required. Name of the web app the slot belongs to.')
param webAppName string

@description('Required. Name of the slot.')
param slotName string

@description('Required. The auth settings for the web app.')
param webAppAuthSettings object

resource webAppStaging 'Microsoft.Web/sites/slots@2022-03-01' existing = {
  name: '${webAppName}/${slotName}'
}

resource webAppStagingAuthSettings 'Microsoft.Web/sites/slots/config@2022-09-01' = {
  name: 'authsettingsV2'
  parent: webAppStaging
  properties: webAppAuthSettings.properties
}
