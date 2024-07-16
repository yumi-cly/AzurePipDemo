# Sample Docker and Kubernetes Node.JS app

This code sample uses the Node.js web framework Express to create a basic web server that listens for HTTP requests on port 8080.

The code includes a Dockerfile in `app/Dockerfile`, which includes the steps to build a container image that can run a Node.js web server. The code sample also includes `deployment.yml` and `service.yml`. `deployment.yml` describe how to deploy the containerized Node.JS application to a Kubernetes cluster. `service.yml` creates a service and a secret resource.

To use the secret resource, you'll need first create a service account and associated secret. See this [Developer Community post](https://developercommunity.visualstudio.com/t/New-Kubernetes-service-connection-causes/10138123#T-N10138393) for more help. 

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.


