# Deploy Jenkins within ECS container behind ALB

## Overview

This code shows the deployment of Jenkins in ECS behind an ALB.
Jenkins plugins are installed within a bootstrap container and
its volume is then shared with the main container.
