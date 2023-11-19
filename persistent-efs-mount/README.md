# Deploy EC2 instance with durable directory

This code shows how to deploy an EC2 instance that, even
after experiencing an outage in its Availability Zone,
persists data in one directory in EFS (which protects against
outages of single AZs).
