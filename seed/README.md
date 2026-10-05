# Seed data

The Timebars Ltd. Strapi database (products, website content, demo and test accounts) and its
uploads — the data the hosted service runs on. Restore it with:

```bash
bash ~/docker/scripts/04-restore.sh      # on the server; loads seed.dump and seed-uploads.tar.gz
```

Files:

| File | What it is |
|---|---|
| `seed.dump` | PostgreSQL custom-format dump (`pg_dump -Fc`) of the Strapi database |
| `seed-uploads.tar.gz` | Strapi `public/uploads` |
| `SHA256SUMS` | checksums, checked by the restore script |

The first Strapi administrator login is listed in the release notes; change its password on first use.
