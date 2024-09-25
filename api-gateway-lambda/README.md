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

To show the Lambda function's logs, one can execute the below:

```bash
LOG_STREAM="$(aws logs describe-log-streams --log-group-name /aws/lambda/parameter_store_lambda --max-items 1 --order-by LastEventTime --descending --query logStreams[].logStreamName --output text | head -n 1)"
aws logs get-log-events --log-group-name /aws/lambda/parameter_store_lambda --log-stream-name "$LOG_STREAM"
```
