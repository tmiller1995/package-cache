import { defineRailway, github, postgres, preserve, project, service, volume } from "railway/iac";

const REPO = "tmiller1995/package-cache";

export default defineRailway(() => {
  // PostgreSQL rather than the embedded H2: Sonatype calls H2-in-a-container
  // unsupported, and Cargo / NuGet v2 are PostgreSQL-only formats in CE.
  const db = postgres("Postgres");
  const data = volume("nexus-data", { sizeMB: 20480 });

  const nexus = service("nexus", {
    source: github(REPO, { branch: "main" }),
    healthcheck: "/service/rest/v1/status",
    healthcheckTimeout: 900, // cold boot is 2-3 min; Railway's default is 300 s
    volumeMounts: { "/nexus-data": data },
    env: {
      PORT: "8081",
      // ponytail: 1.2g heap. The bundled default (2703m) costs ~4 GB RSS at
      // $10/GB-month. Raise if the log shows OutOfMemoryError.
      INSTALL4J_ADD_VM_PARAMS:
        "-Xms1200m -Xmx1200m -XX:MaxDirectMemorySize=1g -Djava.util.prefs.userRoot=/nexus-data/javaprefs",
      NEXUS_DATASTORE_NEXUS_JDBCURL:
        "jdbc:postgresql://${{Postgres.PGHOST}}:${{Postgres.PGPORT}}/${{Postgres.PGDATABASE}}",
      NEXUS_DATASTORE_NEXUS_USERNAME: db.env.PGUSER,
      NEXUS_DATASTORE_NEXUS_PASSWORD: db.env.PGPASSWORD,
    },
  });

  // No public Railway domain: traffic arrives through the Cloudflare Tunnel on
  // the private network. TUNNEL_TOKEN is set once in the dashboard (sealed).
  const cloudflared = service("cloudflared", {
    source: github(REPO, { branch: "main", rootDirectory: "cloudflared" }),
    env: { TUNNEL_TOKEN: preserve() },
  });

  return project("package-cache", { resources: [db, data, nexus, cloudflared] });
});
