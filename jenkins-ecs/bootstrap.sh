#!/bin/bash
set -e
mkdir -p /var/jenkins_home/plugins/ /var/jenkins_home/casc
jenkins-plugin-cli -p \
    authorize-project \
    basic-branch-build-strategies \
    configuration-as-code \
    git \
    jdk-tool \
    job-dsl \
    role-strategy

cp -r -p /usr/share/jenkins/ref/plugins/. /var/jenkins_home/plugins/.

cat >"/var/jenkins_home/casc/jenkins.yaml" <<EOF
jenkins:
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: admin
          password: "$ADMIN_PASSWORD"

  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
EOF
