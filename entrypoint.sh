#!/bin/sh
set -eu
mkdir -p /nexus-data
chown -R 200:200 /nexus-data
# ponytail: no admin-password bootstrap; read /nexus-data/admin.password via
# `railway ssh` once, the onboarding wizard forces a change anyway.
exec su-exec nexus /opt/sonatype/nexus/bin/nexus run
