# Lambda function behind API gateway using Parameter Store

## Overview

This code shows the deployment of a Lambda function behind
a public API gateway. The function code is uploaded to an
S3 bucket and signed by AWS Signer thereafter. The Lambda
function stores/updates one parameter in a Parameter Store.

![Architecture](images/architecture.svg)

## Tests

```bash
terraform init
terraform apply # This will output the API Gateway URL

curl <API Gateway URL>
```
