# Route53 DNS service deployment with DNSSEC

## Overview

This code shows the deployment of a Route53 DNS service
with records being defined in a CSV file. `terraform apply`
will output the assigned name servers for the main domain
(`my.test` by default)

It can be queried like shown below afterwards:

```bash
dig my.test @<name of one of the issued DNS servers>
```

For verification of the DNSSEC record, run

```bash
dig +dnssec +short my.test @<name of one of the issued DNS servers>
```
