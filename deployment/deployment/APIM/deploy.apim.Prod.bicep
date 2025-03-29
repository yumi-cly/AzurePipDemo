@description('The target environment')
@allowed([
  'Dev'
  'Staging'
  'Prod'
])
param environment string = 'Prod'

@description('The sequence number to use in the resource naming')
param sequenceNumber string = '01'

var apiName = 'CORPSCLMMCAAPI'
var apiPath = 'api/clmmca'
var apiDisplayName = 'CORPS CLM MCA API'
var environmentMap = { 
                        prod: 'apim-shared-ecp-prod-westus2-01'
                      }
var productName = 'CORPSCLMMCAAPIProduct'
var serversUrl = 'https://api.corp-prod.premera.com'
var serviceUrl = 'https://app-clm-mca-pd-westus2-${sequenceNumber}.ase-ecp-prod-aseilbv3-02.appserviceenvironment.net/api/ClmListener' 

module apimApisDeploy '../modules/apim/deploy.bicep' = {
  name: apiName
  params: {
    apiManagementServiceName: environmentMap[environment]
    displayName: apiDisplayName
    name: apiName
    path: apiPath
    subscriptionRequired: true
    serviceUrl: serviceUrl 
    value: replace(loadTextContent('./clm-openapi.json'), '{{serversUrl}}', serversUrl)
  }
}

module webhookIntakeOperation '../modules/apim/operations/policies/deploy.bicep' = {
  name: 'webhookIntakeOperation'
  params: {
    apiManagementServiceName: environmentMap[environment]
    apiName: apiName
    operationName: 'webhook-intake'
    format: 'rawxml'
    value: replace(loadTextContent('./apioperation.policy.xml'), '{{backendservice}}', serviceUrl) // Backend service mapping
  }
  dependsOn: [
    apimApisDeploy
  ]
}

module clmmcaProduct '../modules/apim/products/deploy.bicep' = {
  name: 'CORPSCLMMCAAPIProduct'
  params: {
    apiManagementServiceName: environmentMap[environment]
    name: productName
    productDescription: 'CORPSCLMMCAAPIProduct'
    subscriptionRequired: true
  }
  dependsOn: [
    apimApisDeploy
  ]
}

module linkApi '../modules/apim/products/apis/deploy.bicep' = {
  name: 'linkApi'
  params: {
    apiManagementServiceName: environmentMap[environment]
    name: apiName
    productName: productName
  }
  dependsOn: [
    clmmcaProduct
  ]
}

module healthOperationPolicy '../modules/apim/operations/policies/deploy.bicep' = {
  name: 'healthOperationPolicy'
  params: {
    apiManagementServiceName: environmentMap[environment]
    operationName: 'health'
    apiName: apiName
    format: 'rawxml'
    value: replace(loadTextContent('./apioperation.policy.xml'), '{{backendservice}}', '${serviceUrl}${apiPath}')
  }
  dependsOn: [
    apimApisDeploy
  ]
}
