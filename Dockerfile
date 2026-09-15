# Sonatype Nexus Repository Community Edition, wrapped for Railway.
# Railway mounts volumes as root; the upstream image runs as UID 200 with no
# entrypoint, so Nexus cannot write /nexus-data on first boot. The wrapper
# fixes ownership then drops to the nexus user (same pattern as the community
# Railway template). Pin the tag; Railway rebuilds on push, not on upstream.
FROM sonatype/nexus3:3.96.1-alpine
USER root
RUN apk add --no-cache su-exec
COPY entrypoint.sh /usr/local/bin/nexus-entrypoint
RUN chmod +x /usr/local/bin/nexus-entrypoint
EXPOSE 8081
ENTRYPOINT ["/usr/local/bin/nexus-entrypoint"]
