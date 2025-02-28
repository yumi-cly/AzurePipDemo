@description('''
Conditional. Required if the explicit resource name properties are not specified. If specified, overrides the 
corresponding explicit parameter values. An object containing properties required to construct compliant resource 
names. The sum of the length of these parameters shouldn't exceed the maximum length allowed by the 
resource(s) that are deployed. Refer to the Azure documentation for details on length restrictions.

Custom object:
- applicationName: Required. The name of the application.
- departmentCode: Required. The department code.
- environment: Required. The environment name.
- sequenceNumber: Required. The sequence number.
- regionName: Optional. The name of the region to use in the resource name. If not specified, the default 
naming convention for the resource's region name is used.
''')
param resourceName object = {}

@description('Conditional. Required if resourceName.environment is empty. The environment name to use in the resource name. Default: \'dev\'.')
param environment string = (!empty(resourceName) && contains(resourceName, 'environment'))
  ? resourceName.environment
  : 'dev'

@minLength(1)
@maxLength(2) // controls resource name length violations
@description('Conditional. Required if resourceName.sequenceNumber is empty. The sequence number to use in the resource name.')
param sequenceNumber string = (!empty(resourceName) && contains(resourceName, 'sequenceNumber'))
  ? resourceName.sequenceNumber
  : null

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('Conditional. Required if resourceName.applicationName is empty. The application name to use in the resource name.')
param applicationName string = (!empty(resourceName) && contains(resourceName, 'applicationName'))
  ? resourceName.applicationName
  : null

@minLength(1)
@maxLength(8) // controls resource name length violations
@description('Conditional. Required if resourceName.departmentCode is empty. The department code to use in the resource name.')
param departmentCode string = (!empty(resourceName) && contains(resourceName, 'departmentCode'))
  ? resourceName.departmentCode
  : null

@description('Conditional. Required if resourceName.regionName is empty. The region to use in the resource name. Default: resourceGroup().location.')
param regionName string = (!empty(resourceName) && contains(resourceName, 'regionName'))
  ? resourceName.regionName
  : location

@description('Optional. The location to use in the resource name. Only used if resourceName.regionName is empty. Default: resourceGroup().location.')
param location string = resourceGroup().location

@description('Returns the short region name.')
func getShortRegionName(regionName string) string =>
  '${regionName =~ 'westus2' ? 'w2' : regionName =~ 'southcentralus' ? 'sc' : regionName}'

@description('Returns the short environment name.')
func getShortEnvironmentName(environmentName string) string =>
  '${contains(environmentName, '-dev') ? 'dv' : contains(environmentName, '-test') ? 'ts' : contains(environmentName, '-staging') ? 'st' : contains(environmentName, '-prod') ? 'pd' : contains('-nonprod', environmentName) ? 'np' : environmentName}'

@description('Returns the format string based on the resource abbreviation.')
func getFormatString(useShortForm bool) string => useShortForm ? '{0}{1}{2}{3}{4}{5}' : '{0}-{1}-{2}-{3}-{4}-{5}'

@description('Returns the formated resource name.')
func getResourceName(
  resourceAbbreviation string,
  useShortForm bool,
  customFormatString string,
  applicationName string,
  departmentCode string,
  environment string,
  regionName string,
  sequenceNumber string
) string =>
  toLower(format(
    !empty(customFormatString) ? customFormatString : getFormatString(useShortForm),
    resourceAbbreviation,
    applicationName,
    departmentCode,
    useShortForm ? getShortEnvironmentName(environment) : environment,
    useShortForm ? getShortRegionName(regionName) : regionName,
    sequenceNumber
  ))

@description('''An object containing the names of the requested resource. 
Lookup can be done using the resource type name. Examples: 
  myDeployment.outputs.resourceNames.kv
  myDeployment.outputs.resourceNames.st

Descriptions of each type will contain the full name of the resource.
''')
output resourceNames resourceTypes = toObject(
  any(loadJsonContent('./resources.json')),
  x => x.ShortName,
  x =>
    getResourceName(
      x.ShortName,
      x.UseShortForm,
      contains(x, 'CustomFormatString') && !empty(x.CustomFormatString) ? x.CustomFormatString : '',
      applicationName,
      departmentCode,
      environment,
      regionName,
      sequenceNumber
    )
)

// NOTE: this type must be kept in sync with the resource.json.
type resourceTypes = {
  @description('Automation account')
  aa: string
  @description('Communication Services')
  acs: string
  @description('Azure Data Factory')
  adf: string
  @description('Front Door (Standard/Premium) profile')
  afd: string
  @description('Firewall')
  afw: string
  @description('Firewall policy')
  afwp: string
  @description('Azure Monitor action group')
  ag: string
  @description('Application gateway')
  agw: string
  @description('Azure AI services multi-service account')
  aisa: string
  @description('AKS cluster')
  aks: string
  @description('Azure Managed Grafana')
  amg: string
  @description('API management service instance')
  apim: string
  @description('Web app')
  app: string
  @description('App Configuration store')
  appcs: string
  @description('Application Insights')
  appi: string
  @description('Azure Arc enabled Kubernetes cluster')
  arck: string
  @description('Azure Arc enabled server')
  arcs: string
  @description('Azure Stream Analytics')
  asa: string
  @description('App Service environment')
  ase: string
  @description('Application security group (ASG)')
  asg: string
  @description('App Service plan')
  asp: string
  @description('Azure Analysis Services server')
  asserv: string
  @description('Availability set')
  avail: string
  @description('Azure AI Video Indexer')
  avi: string
  @description('Batch accounts')
  ba: string
  @description('Azure Bastion')
  bas: string
  @description('Backup Vault policy')
  bkpol: string
  @description('Bot service')
  bot: string
  @description('Blueprint')
  bp: string
  @description('Blueprint assignment')
  bpa: string
  @description('Backup Vault name')
  bvault: string
  @description('Container apps')
  ca: string
  @description('Container apps environment')
  cae: string
  @description('CDN endpoint')
  cdne: string
  @description('CDN profile')
  cdnp: string
  @description('Container instance')
  ci: string
  @description('Cloud service')
  cld: string
  @description('Content moderator')
  cm: string
  @description('Connections')
  con: string
  @description('Azure Cosmos DB for Apache Cassandra account')
  coscas: string
  @description('Azure Cosmos DB for Apache Gremlin account')
  cosgrm: string
  @description('Azure Cosmos DB for MongoDB account')
  cosmon: string
  @description('Azure Cosmos DB database')
  cosmos: string
  @description('Azure Cosmos DB for NoSQL account')
  cosno: string
  @description('Azure Cosmos DB PostgreSQL cluster')
  cospos: string
  @description('Azure Cosmos DB for Table account')
  costab: string
  @description('Container registry')
  cr: string
  @description('Content safety')
  cs: string
  @description('Custom vision (prediction)')
  cstv: string
  @description('Custom vision (training)')
  cstvt: string
  @description('Computer vision')
  cv: string
  @description('Azure Databricks workspace')
  dbw: string
  @description('Data collection endpoint')
  dce: string
  @description('Azure Monitor data collection rules')
  dcr: string
  @description('Azure Data Explorer cluster')
  dec: string
  @description('Azure Data Explorer cluster database')
  dedb: string
  @description('Disk encryption set')
  des: string
  @description('Document intelligence')
  di: string
  @description('Managed disk (data)')
  disk: string
  @description('Data Lake Analytics account')
  dla: string
  @description('Data Lake Store account')
  dls: string
  @description('Database Migration Service instance')
  dms: string
  @description('DNS forwarding ruleset')
  dnsfrs: string
  @description('DNS private resolver')
  dnspr: string
  @description('Azure Digital Twin instance')
  dt: string
  @description('Event Grid system topic')
  egst: string
  @description('ExpressRoute circuit')
  erc: string
  @description('ExpressRoute gateway')
  ergw: string
  @description('Event Grid domain')
  evgd: string
  @description('Event Grid subscriptions')
  evgs: string
  @description('Event Grid topic')
  evgt: string
  @description('Event hub')
  evh: string
  @description('Event Hubs namespace')
  evhns: string
  @description('Face API')
  face: string
  @description('Front Door (Standard/Premium) endpoint')
  fde: string
  @description('Front Door firewall policy')
  fdfp: string
  @description('Function app')
  func: string
  @description('Gallery')
  gal: string
  @description('HDInsight - Hadoop cluster')
  hadoop: string
  @description('HDInsight - HBase cluster')
  hbase: string
  @description('Health Insights')
  hi: string
  @description('Hosting environment')
  host: string
  @description('Integration account')
  ia: string
  @description('Managed identity')
  id: string
  @description('DNS private resolver inbound endpoint')
  in: string
  @description('IoT hub')
  iot: string
  @description('IP group')
  ipg: string
  @description('Public IP address prefix')
  ippre: string
  @description('Immersive reader')
  ir: string
  @description('Image template')
  it: string
  @description('HDInsight - Kafka cluster')
  kafka: string
  @description('Key vault')
  kv: string
  @description('Key Vault Managed HSM')
  kvmhsm: string
  @description('Language service')
  lang: string
  @description('Load balancer (external)')
  lbe: string
  @description('Load balancer (internal)')
  lbi: string
  @description('Local network gateway')
  lgw: string
  @description('Log Analytics workspace')
  log: string
  @description('Logic app')
  logic: string
  @description('Azure Lab Services lab plan')
  lp: string
  @description('Azure Load Testing instance')
  lt: string
  @description('Maps account')
  map: string
  @description('MariaDB server')
  maria: string
  @description('MariaDB database')
  mariadb: string
  @description('Virtual machine maintenance configuration')
  mc: string
  @description('Management group')
  mg: string
  @description('Azure Migrate project')
  migr: string
  @description('HDInsight - ML Services cluster')
  mls: string
  @description('Azure Machine Learning workspace')
  mlw: string
  @description('MySQL database')
  mysql: string
  @description('NAT gateway')
  ng: string
  @description('Network interface (NIC)')
  nic: string
  @description('AKS user node pool')
  np: string
  @description('AKS system node pool')
  npsystem: string
  @description('Network security group (NSG)')
  nsg: string
  @description('Network security group (NSG) security rules')
  nsgsr: string
  @description('Notification Hubs')
  ntf: string
  @description('Notification Hubs namespace')
  ntfns: string
  @description('Network Watcher')
  nw: string
  @description('Azure OpenAI Service')
  oai: string
  @description('Managed disk (OS)')
  osdisk: string
  @description('DNS private resolver outbound endpoint')
  out: string
  @description('Log Analytics query packs')
  pack: string
  @description('Power BI Embedded')
  pbi: string
  @description('Provisioning services certificate')
  pcert: string
  @description('Virtual network peering')
  peer: string
  @description('Private endpoint')
  pep: string
  @description('Public IP address')
  pip: string
  @description('Private Link')
  pl: string
  @description('Proximity placement group')
  ppg: string
  @description('Provisioning services')
  provs: string
  @description('PostgreSQL database')
  psql: string
  @description('Microsoft Purview instance')
  pview: string
  @description('Azure Cache for Redis instance')
  redis: string
  @description('Route filter')
  rf: string
  @description('Resource group')
  rg: string
  @description('Restore point collection')
  rpc: string
  @description('Recovery Services vault')
  rsv: string
  @description('Route table')
  rt: string
  @description('Route server')
  rtserv: string
  @description('Load balancer rule')
  rule: string
  @description('Service Bus namespace')
  sbns: string
  @description('Service Bus queue')
  sbq: string
  @description('Service Bus topic')
  sbt: string
  @description('Service Bus topic subscription')
  sbts: string
  @description('Service endpoint policy')
  se: string
  @description('Service Fabric cluster')
  sf: string
  @description('Service Fabric managed cluster')
  sfmc: string
  @description('File share')
  share: string
  @description('SignalR')
  sigr: string
  @description('Snapshot')
  snap: string
  @description('Virtual network subnet')
  snet: string
  @description('HDInsight - Spark cluster')
  spark: string
  @description('Speech service')
  spch: string
  @description('Azure SQL Database server')
  sql: string
  @description('Azure SQL database')
  sqldb: string
  @description('Azure SQL Elastic Pool')
  sqlep: string
  @description('Azure SQL Elastic Job agent')
  sqlja: string
  @description('SQL Managed Instance')
  sqlmi: string
  @description('SQL Server Stretch Database')
  sqlstrdb: string
  @description('AI Search')
  srch: string
  @description('SSH key')
  sshkey: string
  @description('Azure StorSimple')
  ssimp: string
  @description('Storage Sync Service name')
  sss: string
  @description('Storage account')
  st: string
  @description('Static web app')
  stapp: string
  @description('HDInsight - Storm cluster')
  storm: string
  @description('VM storage account')
  stvm: string
  @description('Azure Synapse Analytics SQL Dedicated Pool')
  syndp: string
  @description('Azure Synapse Analytics private link hub')
  synplh: string
  @description('Azure Synapse Analytics Spark Pool')
  synsp: string
  @description('Azure Synapse Analytics workspaces')
  synw: string
  @description('Traffic Manager profile')
  traf: string
  @description('Translator')
  trsl: string
  @description('Template specs name')
  ts: string
  @description('Time Series Insights environment')
  tsi: string
  @description('User defined route (UDR)')
  udr: string
  @description('VPN connection')
  vcn: string
  @description('Virtual desktop application group')
  vdag: string
  @description('Virtual desktop host pool')
  vdpool: string
  @description('Virtual desktop scaling plan')
  vdscaling: string
  @description('Virtual desktop workspace')
  vdws: string
  @description('Virtual network gateway')
  vgw: string
  @description('Virtual WAN Hub')
  vhub: string
  @description('Virtual machine')
  vm: string
  @description('Virtual Machine Scale Set Prefix')
  vmprefix: string
  @description('Virtual machine scale set')
  vmss: string
  @description('Virtual network')
  vnet: string
  @description('Virtual network manager')
  vnm: string
  @description('VPN Gateway')
  vpng: string
  @description('VPN site')
  vst: string
  @description('Virtual WAN')
  vwan: string
  @description('Web Application Firewall (WAF) policy')
  waf: string
  @description('Web Application Firewall (WAF) policy rule group')
  wafrg: string
  @description('WebPubSub')
  wps: string
}

// NOTE: the following outputs are used for legacy support.
@description('[DEPRECATED]. Use outputs.resourceNames.aks instead. This will be removed sometime after 10/19/2024.')
output aks string = toLower('aks-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.appcs instead. This will be removed sometime after 10/19/2024.')
output appConfig string = toLower('appConfig-${applicationName}-${departmentCode}-${environment}-${getShortRegionName(regionName)}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.agw instead. This will be removed sometime after 10/19/2024.')
output agw string = toLower('agw-${applicationName}-${departmentCode}-${environment}-${getShortRegionName(regionName)}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.agw instead. This will be removed sometime after 10/19/2024.')
output appGateway string = toLower('agw-${applicationName}-${departmentCode}-${environment}-${getShortRegionName(regionName)}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.adf instead. This will be removed sometime after 10/19/2024.')
output adf string = toLower('adf-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.asp instead. This will be removed sometime after 10/19/2024.')
output asp string = toLower('asp-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.adf instead. This will be removed sometime after 10/19/2024.')
output azureDataFactory string = toLower('adf-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.sql instead. This will be removed sometime after 10/19/2024.')
output azureSql string = toLower('sql-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.cr instead. This will be removed sometime after 10/19/2024.')
output containerRegistry string = toLower('acr${applicationName}${departmentCode}${environment}${regionName}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.cosmos instead. This will be removed sometime after 10/19/2024.')
output cosmosDb string = toLower('cosmosDb-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.evh or outputs.resourceNames.evhns instead. This will be removed sometime after 10/19/2024.')
output eventHub string = toLower('evhns-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.func instead. This will be removed sometime after 10/19/2024.')
output functionApp string = toLower('func-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.kv instead. This will be removed sometime after 10/19/2024.')
output keyVault string = toLower('kv${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.sb instead. This will be removed sometime after 10/19/2024.')
output serviceBus string = toLower('sb-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.sshkey instead. This will be removed sometime after 10/19/2024.')
output sshkey string = toLower('sshkey-${applicationName}-${departmentCode}-${getShortEnvironmentName(environment)}-${getShortRegionName(regionName)}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.sqlmi instead. This will be removed sometime after 10/19/2024.')
output sqlMi string = toLower('sqlmi-${applicationName}-${departmentCode}-${environment}-${regionName}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.st instead. This will be removed sometime after 10/19/2024.')
output storageAccount string = toLower('st${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}${substring(uniqueString(resourceGroup().id), 0, 4)}')

@description('[DEPRECATED]. Use outputs.resourceNames.app instead. This will be removed sometime after 10/19/2024.')
output webApp string = toLower('app-${applicationName}-${departmentCode}-${environment}-${location}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.traf instead. This will be removed sometime after 10/19/2024.')
output trafficManager string = toLower('traf-${applicationName}-${departmentCode}-${environment}-${location}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.ppg instead. This will be removed sometime after 10/19/2024.')
output proximityPlacementGroup string = toLower('ppg-${applicationName}-${departmentCode}-${environment}-${location}-${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.vm instead. This will be removed sometime after 10/19/2024.')
output virtualMachine string = toLower('vm${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.vmss instead. This will be removed sometime after 10/19/2024.')
output vmss string = toLower('vmss${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.lbi instead. This will be removed sometime after 10/19/2024.')
output lbi string = toLower('lbi${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.lbe instead. This will be removed sometime after 10/19/2024.')
output lbe string = toLower('lbe${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.rule instead. This will be removed sometime after 10/19/2024.')
output rule string = toLower('rule${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.lbi instead. This will be removed sometime after 10/19/2024.')
output internalLoadBalancer string = toLower('lbi${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.lbe instead. This will be removed sometime after 10/19/2024.')
output externalLoadBalancer string = toLower('lbe${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')

@description('[DEPRECATED]. Use outputs.resourceNames.rule instead. This will be removed sometime after 10/19/2024.')
output loadBalancerRule string = toLower('rule${applicationName}${departmentCode}${getShortEnvironmentName(environment)}${getShortRegionName(regionName)}${sequenceNumber}')
