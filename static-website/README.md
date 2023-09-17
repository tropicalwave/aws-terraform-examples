# Static site deployment with Cloudfront and S3

## Overview

![Architecture](images/architecture.svg)

## Notes

After `terraform apply`, terraform will not wait for
the Cloudfront deployment to be finished
(ie. `wait_for_deployment` is set to false). Therefore,
the site might not be accessible immediately.
