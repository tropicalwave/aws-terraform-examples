# Static site deployment with ALB and Lambda

## Overview

At times, a Cloudfront deployment may not be feasible for serving
static content. In this case - and especially if low traffic
is expected - an alternative option is the use of an ALB that
executes a Lambda function which retrieves and returns the file
contents. This is what this code example shows.
