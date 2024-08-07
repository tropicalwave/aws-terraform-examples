# Lambda function behind private API gateway behind ALB

## Overview

This code shows the deployment of a Lambda function behind
a private API gateway that is located behind an ALB. Additionally,
the API gateway is located in a different VPC attached to the
ALB VPC via a transit gateway.

![Architecture](images/architecture.svg)

## Tests

```bash
terraform init
terraform apply # This will output the URL

curl <URL>
```
