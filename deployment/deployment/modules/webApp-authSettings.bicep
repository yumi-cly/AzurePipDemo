// taken & modified from https://dev.azure.com/pbc/Premera/_git/VA_EmsApimRouting?path=/.pipelines/infra/shared/bicep/infra-shared-webAppAuth.bicep

@description('Required. The tenant of the OID issuer.')
param tenantId string = tenant().tenantId

@description('Required. The name of the web app.')
param webAppName string

@description('Optional. The names of the slots to apply the auth settings to.')
param slotNames string[] = []

@description('Required. The client ID of the app registration.')
param appRegistrationClientId string

@description('Optional. The allowed audiences for the web app.')
param allowedAudiences string[] = []

@description('Optional. The allowed identities for the web app. Typically the object/principal id.')
param allowedIdentities string[] = []

@description('Optional. The allowed applications for the web app. Typically the client/application id.')
param allowedApplications string[] = []

resource webApp 'Microsoft.Web/sites@2022-03-01' existing = {
  name: webAppName
}

resource webAppAuthSettings 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'authsettingsV2'
  parent: webApp
  properties: {
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        login: {
          disableWWWAuthenticate: false
        }
        registration: {
          clientId: appRegistrationClientId
          openIdIssuer: 'https://sts.windows.net/${tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: allowedAudiences
          defaultAuthorizationPolicy: {
            allowedApplications: union(allowedApplications, [appRegistrationClientId])
            allowedPrincipals: {
              identities: allowedIdentities
            }
          }
        }
      }
    }
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
  }
}

module webAppAuthSettingsSlots 'webApp-authSettings-slot.bicep' = [for slotName in slotNames: {
  name: slotName
  params: {
    webAppName: webAppName
    slotName: slotName
    webAppAuthSettings: webAppAuthSettings
  }
}]
