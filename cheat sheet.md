


# How to Change password on strapi admin user
docker exec tbpgdb psql -U strapi -d strapi -Atc "select email from admin_users"   # which email to use
docker exec -it tbbe strapi admin:reset-user-password                                # asks email, then the new password