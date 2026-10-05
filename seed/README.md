# Seed data

Demo data for a first start: a Strapi database dump with products and demo accounts (no real
users or customers), plus the matching uploads. Restore it with:

```bash
bash ~/docker/scripts/04-restore.sh ~/docker/seed/seed.dump ~/docker/seed/seed-uploads.tar.gz      # on the server
```

Files (added before release `v1.0.0`):

| File | What it is |
|---|---|
| `seed.dump` | PostgreSQL custom-format dump (`pg_dump -Fc`) of the Strapi database |
| `seed-uploads.tar.gz` | Strapi `public/uploads` |
| `SHA256SUMS` | checksums, checked by the restore script |

The first Strapi administrator login is listed in the release notes; change its password on first use.
