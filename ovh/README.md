# package-cache on OVHcloud

Nexus Repository CE, PostgreSQL 18 and a Cloudflare Tunnel connector on one
OVHcloud VPS, replacing the Railway deployment. Clients keep using the same
`<host>.tylersoftwaredeveloper.com` URL, and the Postgres database and
`/nexus-data` move over intact, so the `ci` user, its token, the repositories
and the FontAwesome credentials all survive. **No `.npmrc`, `nuget.config` or
`.cargo/config.toml` changes in Meeple Guild or Perfect Path.**

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | postgres, nexus (built from the repo-root `Dockerfile`), cloudflared |
| `.env.example` | secrets and memory knobs; copy to `.env` on the VPS |
| `bootstrap-vps.sh` | one-time hardening + Docker + checkout on a fresh Ubuntu 24.04 VPS |
| `backup.sh` | nightly `pg_dump`, 7-day retention (installed by bootstrap) |

Placeholders below: `<host>` is the production hostname, `<test-host>` is a
temporary second hostname for testing (for example `nexus-ovh`), `<vps-ip>` is
the VPS address.

---

## Migration runbook

Hands-on time is about an hour. The only downtime is the cutover window in
step 6, roughly 15 minutes, during which the cache is unreachable. Do step 6
when no builds are running.

Nexus 3.91 removed the Read-Only (freeze) API, so the cutover quiesces Railway
by taking its hostname off the Railway tunnel instead: every client request
arrives through that tunnel, so no new components get written while the final
copy runs.

### 1. Order the VPS

- OVHcloud US, **VPS-3** (6 vCores / 12 GB / 100 GB NVMe), US-East (Vint Hill),
  **Ubuntu 24.04**. Not a Local Zone (no Docker support there).
- Add your SSH public key during the order. OVH puts it on the `ubuntu` user.
- VPS-2 (8 GB) also works; use the smaller memory values in `.env.example`.

### 2. Bootstrap the VPS

```sh
ssh ubuntu@<vps-ip>
# Until this branch is merged, use .../ovh-migration/ovh/bootstrap-vps.sh
curl -fsSL https://raw.githubusercontent.com/tmiller1995/package-cache/main/ovh/bootstrap-vps.sh -o bootstrap-vps.sh
sudo bash bootstrap-vps.sh
exit   # log back in so the docker group applies
```

If the branch is not merged yet, also run
`git -C /opt/package-cache checkout ovh-migration`.

### 3. Create the new Cloudflare tunnel

Zero Trust -> Networks -> Tunnels -> **Create a tunnel** -> Cloudflared ->
name `package-cache-ovh`. Copy the token from the Docker install command.
Then add a public hostname **`<test-host>`** -> HTTP -> `nexus:8081`.
Leave the production hostname on the Railway tunnel for now.

```sh
cd /opt/package-cache/ovh
cp .env.example .env && chmod 600 .env
# fill in POSTGRES_PASSWORD (openssl rand -base64 32) and TUNNEL_TOKEN
docker compose up -d postgres
```

Do not start nexus yet: an empty database would initialise a brand-new
instance on top of which the restore cannot go.

### 4. Give Railway's containers a temporary push key

Both transfers run *from* the Railway containers *to* the VPS over SSH, which
is binary-safe and avoids exposing Railway Postgres publicly.

In the Railway nexus container (`railway ssh --service nexus`):

```sh
apk add --no-cache openssh-client rsync
ssh-keygen -t ed25519 -N '' -f /root/.ssh/migrate -C railway-migrate
cat /root/.ssh/migrate.pub
```

On the VPS, allow that key with no shell features, and make a staging folder:

```sh
echo 'restrict <paste the migrate.pub line>' >> ~/.ssh/authorized_keys
mkdir -p ~/import
```

### 5. Pre-sync the blob store (live, no downtime)

From the Railway nexus container, copy `/nexus-data` (~4 GB) while Nexus keeps
serving. Step 6 only sends the difference.

```sh
rsync -az --delete --exclude log/ --exclude tmp/ --exclude cache/ \
  -e "ssh -i /root/.ssh/migrate -o StrictHostKeyChecking=accept-new" \
  /nexus-data/ ubuntu@<vps-ip>:import/nexus-data/
```

### 6. Cutover window

1. **Take Railway offline.** In Zero Trust, on the Railway tunnel, delete the
   `<host>` public hostname (and its DNS record when asked). Clients now get
   errors and nothing new is written to Railway's Nexus.
2. **Final blob sync**: rerun the step 5 `rsync` in the nexus container.
3. **Dump the database** from the Railway Postgres container
   (`railway ssh --service Postgres`), streaming straight to the VPS. Copy
   the private key over first (print it with `cat /root/.ssh/migrate` in the
   nexus container and paste it into the same path here), then:
   ```sh
   apt-get update && apt-get install -y openssh-client
   chmod 600 /root/.ssh/migrate
   pg_dump -U "$PGUSER" -d "$PGDATABASE" -Fc \
     | ssh -i /root/.ssh/migrate -o StrictHostKeyChecking=accept-new \
         ubuntu@<vps-ip> 'cat > import/nexus.dump'
   ```
4. **Restore and start on the VPS**:
   ```sh
   cd /opt/package-cache/ovh
   docker compose exec -T postgres \
     pg_restore -U nexus -d nexus --no-owner --no-privileges < ~/import/nexus.dump
   docker compose exec postgres psql -U nexus -d nexus \
     -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
   sudo rsync -a --delete ~/import/nexus-data/ /srv/package-cache-data/nexus-data/
   sudo chown -R 200:200 /srv/package-cache-data/nexus-data
   docker compose up -d --build
   docker compose logs -f nexus   # wait for "Started Sonatype Nexus COMMUNITY"
   ```
   The table count should be in the dozens, not zero. `pg_restore` warnings
   about objects that already exist (for example `schema public`) are
   harmless; errors about `pg_trgm` or failed table creation are not.
5. **Smoke test through `<test-host>`**:
   ```sh
   curl -fsS -u admin https://<test-host>/service/rest/v1/repositories | grep '"name"'
   curl -fsS -u '<ci-user>:<ci-token>' https://<test-host>/repository/npm-group/lodash | head -c 200; echo
   curl -fsS -u '<ci-user>:<ci-token>' https://<test-host>/repository/nuget-group/index.json | head -c 200; echo
   curl -fsS -u '<ci-user>:<ci-token>' https://<test-host>/repository/cargo-proxy/config.json; echo
   ```
   The first call should list `npm-proxy`, `npm-fontawesome`, `npm-group`,
   `nuget-proxy`, `nuget-group` and `cargo-proxy`; the others prove the `ci`
   token still works. Also fetch a package that was *not* cached yet, to prove
   the proxies reach upstream (FontAwesome included).
6. **Point production at OVH.** On `package-cache-ovh`, add the public
   hostname `<host>` -> HTTP -> `nexus:8081`.
   ```sh
   curl -fsS https://<host>/service/rest/v1/status -o /dev/null -w '%{http_code}\n'   # 200
   ```

### 7. Verify

- Re-run the latest CI workflow in Meeple Guild and Perfect Path, plus one
  Railway deploy of each app, and confirm restores succeed.
- `docker stats --no-stream` after a few builds: Nexus should sit well under
  6 GB, Postgres under 1.5 GB.
- Remove the `railway-migrate` line from `~/.ssh/authorized_keys`, delete
  `~/import`, and delete the `<test-host>` public hostname.

### Rollback

Railway is untouched; it only lost its hostname. Delete `<host>` from
`package-cache-ovh` and add it back to the Railway tunnel ->
`http://nexus.railway.internal:8081`. Anything cached on OVH in the meantime
is simply fetched again by Railway.

### 8. Decommission Railway (after about a week)

1. Delete the `package-cache` project in Railway.
2. Delete the old Railway tunnel in Zero Trust.
3. Follow-up PR: remove `.railway/`, `.github/workflows/railway-config.yml`,
   `package.json`, `package-lock.json` and `cloudflared/`; rewrite the root
   README around `ovh/`; delete the `RAILWAY_TOKEN` repository secret.
4. When a Nexus release after 3.96.3 ships, bump the tag in `Dockerfile` and
   drop the rate-limiter workaround in `entrypoint.sh`.

---

## Day-to-day

```sh
cd /opt/package-cache && git pull && cd ovh && docker compose up -d --build   # deploy a change
docker compose logs -f nexus                                                  # logs
ls -lh /srv/package-cache-data/backups                                       # nightly dumps
```

Restore a dump: `docker compose stop nexus`, then
`docker compose exec -T postgres pg_restore -U nexus -d nexus --clean --if-exists --no-owner < <file>`,
then `docker compose start nexus`.
