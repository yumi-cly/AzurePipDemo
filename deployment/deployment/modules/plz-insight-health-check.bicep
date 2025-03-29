@description('Optional. The location to deploy resources to. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Required. The name of the alert.')
param name string

@description('Required. Environment to be deployed to.')
param environment string

@description('Optional. The list of resource IDs that this metric alert is scoped to.')
param scopes array = [ ]

@description('Conditional. The resource type of the target resource(s) on which the alert is created/updated. Required if alertCriteriaType is MultipleResourceMultipleMetricCriteria.')
param targetResourceType string?

@description('Conditional. The region of the target resource(s) on which the alert is created/updated. Required if alertCriteriaType is MultipleResourceMultipleMetricCriteria.')
param targetResourceRegion string = location

@description('Optional. The flag that indicates whether the alert should be auto resolved or not.')
param autoMitigate bool = true

@description('Optional. Description of the alert.')
param alertDescription string = ''

@description('Optional. Indicates whether this alert is enabled.')
param enabled bool = true

@description('Optional. The severity of the alert.')
@allowed([
  0
  1
  2
  3
  4
])
param severity int = 2

@description('Optional. how often the metric alert is evaluated represented in ISO 8601 duration format.')
@allowed([
  'PT1M'
  'PT5M'
  'PT15M'
  'PT30M'
  'PT1H'
])
param evaluationFrequency string = 'PT5M'

@description('Optional. the period of time (in ISO 8601 duration format) that is used to monitor alert activity based on the threshold.')
@allowed([
  'PT1M'
  'PT5M'
  'PT15M'
  'PT30M'
  'PT1H'
  'PT6H'
  'PT12H'
  'P1D'
])
param windowSize string = 'PT15M'

@description('Optional. The list of action group resource Ids to apply when the alert triggers. When used with the enableSharedServiceNowActionGroup flag, the shared ServiceNow action group will be added to the list of action groups.')
param actionGroupResourceIds array = []

@description('Optional. The flag that indicates whether the shared ServiceNow action group should be enabled or not.')
param enableSharedServiceNowActionGroup bool = true

@description('''The resource ID of the shared service-now action group. To use the dev or UAT service-now action group, 
update the value below to use the resource Id from the desired action group. Default value is the production service-now 
action group which is appropriate for use in all environments.''')
// var sharedServiceNowActionGroupResourceId = sharedResources.outputs.serviceNowActionGroupResourceId

var actionGroupMap = {
  Dev:'/subscriptions/69688874-B43B-4DCB-AB24-F00F51953599/resourceGroups/rg-coreservices-law-nonprod-westus2-01/providers/microsoft.insights/actiongroups/AG-AlertingServiceNowDev-Non Prod-Global-01'
  Staging:'/subscriptions/bc060021-2328-439e-b220-05121a188f1f/resourceGroups/rg-coreservices-law-prod-westus2-01/providers/microsoft.insights/actiongroups/ag-alertingservicenowuat-prod-global-01'
  Prod: '/subscriptions/bc060021-2328-439e-b220-05121a188f1f/resourceGroups/rg-coreservices-law-prod-westus2-01/providers/microsoft.insights/actiongroups/ag-alertingservicenowprod-prod-global-01'
}
// dev service-now action group resource id:
var sharedServiceNowActionGroupResourceId = environment == 'Staging' || environment == 'st' ? actionGroupMap.Staging
                                          : environment == 'Dev' || environment == 'dv' ? actionGroupMap.Dev
                                          : environment == 'Prod' || environment == 'pd' ? actionGroupMap.Prod
                                          : actionGroupMap.Dev

@allowed(
  [
    'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
  ]
)
@description('Optional. Maps to the \'odata.type\' field. Specifies the type of the alert criteria. Default: Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria')
param alertCriteriaType string = 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'

module sharedResources 'br:pbcbicepprod.azurecr.io/ecp/shared-resources:2.0-preview' = {
  name: '${uniqueString(deployment().name, location)}-sharedResources'
  params: {
    location: location
  }
}

module metricAlert 'br/public:avm/res/insights/metric-alert:0.3.0' = {
  name: '${uniqueString(deployment().name, location)}-metricAlertDeployment'
  params: {
    // Required parameters
    name: name
    alertDescription: alertDescription
    criteria: {
      #disable-next-line BCP225 // type is validated by the allowed values
      'odata.type': alertCriteriaType
      allof: [
        {
          threshold: 99
          name: 'HealthCheck'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'HealthCheckStatus'
          operator: 'LessThan'
          timeAggregation: 'Average'
          skipMetricValidation: false
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    // Non-required parameters
    actions: enableSharedServiceNowActionGroup ? union(actionGroupResourceIds, [sharedServiceNowActionGroupResourceId]) : actionGroupResourceIds
    enabled: enabled
    evaluationFrequency: evaluationFrequency
    location: 'global'
    scopes: scopes
    targetResourceType: targetResourceType
    targetResourceRegion: targetResourceRegion
    windowSize: windowSize
    autoMitigate: autoMitigate
    severity: severity
    enableTelemetry: false
    tags: resourceGroup().tags
  }
}
