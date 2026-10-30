# Docker Image Versions

Image pins of the stack and their history. The source of truth is `docker/docker-compose.yml`
and the `FROM` line of `docker/Dockerfile.db`; record every change here.

## Current pins

| Service | Image |
|---|---|
| db | `supabase/postgres:15.8.1.085` (base of `Dockerfile.db`) |
| studio | `supabase/studio:2025.11.10-sha-5291fe3` |
| auth | `supabase/gotrue:v2.182.1` |
| rest | `postgrest/postgrest:v13.0.7` |
| realtime | `supabase/realtime:v2.63.0` |
| storage | `supabase/storage-api:v1.29.0` |
| meta | `supabase/postgres-meta:v0.93.1` |
| functions | `supabase/edge-runtime:v1.69.23` |
| analytics | `supabase/logflare:1.22.6` |
| supavisor | `supabase/supavisor:2.7.4` |
| kong | `kong:2.8.1` |
| vector | `timberio/vector:0.28.1-alpine` |
| imgproxy | `darthsim/imgproxy:v3.8.0` |
| mail | `inbucket/inbucket:3.0.3` |

The four non-Supabase images (kong, vector, imgproxy, mail) have not changed in the history
below.

## History

### 2025-11-12
- supabase/studio:2025.11.10-sha-5291fe3 (prev 2025.10.27-sha-85b84e0) — [dashboard updates](https://github.com/orgs/supabase/discussions/40083)
- supabase/gotrue:v2.182.1 (prev v2.180.0) — [release](https://github.com/supabase/auth/releases/tag/v2.182.1)
- supabase/realtime:v2.63.0 (prev v2.57.2) — [release](https://github.com/supabase/realtime/releases/tag/v2.63.0)
- supabase/storage-api:v1.29.0 (prev v1.28.2) — [release](https://github.com/supabase/storage/releases/tag/v1.29.0)
- supabase/edge-runtime:v1.69.23 (prev v1.69.15) — [release](https://github.com/supabase/edge-runtime/releases/tag/v1.69.23)
- supabase/supavisor:2.7.4 (prev 2.7.3) — [release](https://github.com/supabase/supavisor/releases/tag/v2.7.4)

### 2025-10-28
- supabase/studio:2025.10.27-sha-85b84e0 (prev 2025.10.20-sha-5005fc6)
- supabase/realtime:v2.57.2 (prev v2.56.0)
- supabase/storage-api:v1.28.2 (prev v1.28.1)
- supabase/postgres-meta:v0.93.1 (prev v0.93.0)
- supabase/edge-runtime:v1.69.15 (prev v1.69.14)

### 2025-10-21
- supabase/studio:2025.10.20-sha-5005fc6 (prev 2025.10.01-sha-8460121)
- supabase/realtime:v2.56.0 (prev v2.51.11)
- supabase/storage-api:v1.28.1 (prev v1.28.0)
- supabase/postgres-meta:v0.93.0 (prev v0.91.6)
- supabase/edge-runtime:v1.69.14 (prev v1.69.6)
- supabase/supavisor:2.7.3 (prev 2.7.0)

### 2025-10-13
- supabase/logflare:1.22.6 (prev 1.22.4)

### 2025-10-08
- supabase/studio:2025.10.01-sha-8460121 (prev 2025.06.30-sha-6f5982d)
- supabase/gotrue:v2.180.0 (prev v2.177.0)
- postgrest/postgrest:v13.0.7 (prev v12.2.12)
- supabase/realtime:v2.51.11 (prev v2.34.47)
- supabase/storage-api:v1.28.0 (prev v1.25.7)
- supabase/postgres-meta:v0.91.6 (prev v0.91.0)
- supabase/logflare:1.22.4 (prev 1.14.2)
- supabase/postgres:15.8.1.085 (prev 15.8.1.060)
- supabase/supavisor:2.7.0 (prev 2.5.7)

### 2025-07-15
- supabase/gotrue:v2.177.0 (prev v2.176.1)
- supabase/storage-api:v1.25.7 (prev v1.24.7)
- supabase/postgres-meta:v0.91.0 (prev v0.89.3)
- supabase/supavisor:2.5.7 (prev 2.5.6)

### 2025-07-02
- supabase/studio:2025.06.30-sha-6f5982d (prev 2025.06.02-sha-8f2993d)
- supabase/gotrue:v2.176.1 (prev v2.174.0)
- supabase/storage-api:v1.24.7 (prev v1.23.0)
- supabase/supavisor:2.5.6 (prev 2.5.1)

### 2025-06-03
- supabase/studio:2025.06.02-sha-8f2993d (prev 2025.05.19-sha-3487831)
- supabase/gotrue:v2.174.0 (prev v2.172.1)
- supabase/storage-api:v1.23.0 (prev v1.22.17)
- supabase/postgres-meta:v0.89.3 (prev v0.89.0)
