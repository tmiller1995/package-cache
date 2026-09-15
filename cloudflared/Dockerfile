# Cloudflare Tunnel connector. TUNNEL_TOKEN (set on the Railway service) selects
# the tunnel; the public hostname -> http://nexus.railway.internal:8081 route is
# configured in the Cloudflare Zero Trust dashboard. Same pattern as Meeple Guild.
FROM cloudflare/cloudflared:latest
USER nonroot
ENTRYPOINT ["cloudflared"]
CMD ["tunnel", "--no-autoupdate", "--metrics", "[::]:2000", "run"]
