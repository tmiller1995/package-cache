# package-cache

Sonatype Nexus Repository Community Edition on Railway: a private pull-through
cache for npm (incl. the FontAwesome Pro registry), NuGet and Cargo, shared by
Meeple Guild and Perfect Path. Reached through a Cloudflare Tunnel on
tylersoftwaredeveloper.com; no public Railway domain.

Everything Railway-side is declared in `.railway/railway.ts` (Railway
Infrastructure as Code). `railway.toml` is deprecated and not used here.

## Deploy / change

    npm install
    railway login && railway link      # once
    railway config plan
    railway config apply

PRs that touch `.railway/**` get a plan comment; merging applies it
(`.github/workflows/railway-config.yml`, needs the `RAILWAY_TOKEN` secret).

## First boot (once)

1. Set `TUNNEL_TOKEN` on the cloudflared service (sealed) and route
   `<host>.tylersoftwaredeveloper.com -> http://nexus.railway.internal:8081`
   in Cloudflare Zero Trust.
2. If Nexus logs that `pg_trgm` is missing: `railway connect Postgres` then
   `CREATE EXTENSION IF NOT EXISTS pg_trgm;`.
3. Initial admin password: `railway ssh --service nexus -- cat /nexus-data/admin.password`.
   Sign in, accept the CE EULA, set a new password, disable anonymous access.
4. Create repos: `npm-proxy` (registry.npmjs.org) + `npm-fontawesome`
   (npm.fontawesome.com, auth type Preemptive Bearer Token) -> `npm-group`;
   `nuget-proxy` -> `nuget-group`; `cargo-proxy`.
5. Create a `ci` user with a read-only repository-view role; use its user token
   in each consuming repo's `.npmrc` / `nuget.config` / `.cargo/config.toml`.

## Knobs

- JVM heap: `INSTALL4J_ADD_VM_PARAMS` in `railway.ts`. Bundled default is 2.7 GB;
  we start at 1.2 GB. Raise on OutOfMemoryError.
- If cloudflared cannot reach Nexus over the IPv6 private network, add
  `-Dapplication-host=::` to the same variable.
- CE limits: 100k requests/day, 40k components. Usage Center on the Nexus home page.
