#!/bin/sh
set -eu
mkdir -p /nexus-data
chown -R 200:200 /nexus-data
# Nexus 3.94.0-3.96.3 known issue (3.96 release notes): once the auth rate limiter
# trips, every further attempt, even with valid credentials, restarts the lockout.
# The whole cache shares the "ci" user, so a few bad logins locked out all CI for
# 15+ minutes at a time. Sonatype's workaround is to disable the limiter.
# ponytail: re-enable (drop these lines) once a release after 3.96.3 fixes it.
props=/nexus-data/etc/nexus.properties
mkdir -p /nexus-data/etc
touch "$props"
sed -i '/^nexus\.auth\.ratelimit\.enabled=/d' "$props"
echo 'nexus.auth.ratelimit.enabled=false' >> "$props"
chown 200:200 /nexus-data/etc "$props"
# ponytail: no admin-password bootstrap; read /nexus-data/admin.password via
# `railway ssh` once, the onboarding wizard forces a change anyway.
exec su-exec nexus /opt/sonatype/nexus/bin/nexus run
