# hw04 — развёртывание физической репликации (GCP, 3 ВМ, PostgreSQL 18.4)
# postgres4 (10.132.0.5) — мастер, postgres4r (10.132.0.6) — реплика 1, postgres4r2 (10.132.0.7) — реплика 2
# На всех ВМ: PG 18 (PGDG) + конфиг курса (shared_buffers 4GB, wal_writer_delay 200ms, max_slot_wal_keep_size 1000MB, ...)
# Учебная БД thai_medium на мастере: book.tickets = 53 997 475 строк.

### МАСТЕР (postgres4) ###
cat >> /etc/postgresql/18/main/postgresql.conf << EOL
listen_addresses = '10.132.0.5,localhost'
max_wal_senders = 4
EOL
cat >> /etc/postgresql/18/main/pg_hba.conf << EOL
host replication replicator 10.132.0.0/20 scram-sha-256
EOL
sudo systemctl restart postgresql@18-main         # ВАЖНО: кластер под systemd — рестарт только так, не `pg_ctlcluster` без sudo
psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secret\$123';"

### РЕПЛИКА 1 (postgres4r) и РЕПЛИКА 2 (postgres4r2) ###
# .pgpass в доме postgres (/var/lib/postgresql/.pgpass), а не в /home/<user>!
tee /var/lib/postgresql/.pgpass << 'EOL'
*:5432:*:replicator:secret$123
EOL
chmod 0600 /var/lib/postgresql/.pgpass
systemctl stop postgresql@18-main
rm -rf /var/lib/postgresql/18/main
pg_basebackup -h 10.132.0.5 -U replicator -X stream -C -S slot_r1 -v -R -D /var/lib/postgresql/18/main   # r2: -S slot_r2
# ГРАБЛИ: реплика не стартует, пока max_wal_senders < мастерского. Поднять ДО старта:
tee -a /etc/postgresql/18/main/postgresql.conf << 'EOL'
max_wal_senders = 4
listen_addresses = '10.132.0.6,localhost'
EOL
systemctl start postgresql@18-main
psql -c "ALTER SYSTEM SET cluster_name='postgres4r';"   # имя для synchronous_standby_names (дефолт=FQDN с точками — нельзя)
systemctl restart postgresql@18-main

# Время pg_basebackup (~12 ГБ): r1 = 49.5 c, r2 (с мастера) = 34.9 c.

### КАСКАД: перецепить r2 на r1 ###
# на r1: разрешить репликацию и создать слот (на standby можно с PG 16+)
echo "host replication replicator 10.132.0.0/20 scram-sha-256" >> /etc/postgresql/18/main/pg_hba.conf
systemctl reload postgresql@18-main
psql -c "SELECT pg_create_physical_replication_slot('slot_cascade');"
# на r2: перезалить уже с r1
systemctl stop postgresql@18-main
rm -rf /var/lib/postgresql/18/main
pg_basebackup -h 10.132.0.6 -U replicator -X stream -S slot_cascade -v -R -D /var/lib/postgresql/18/main
systemctl start postgresql@18-main
psql -c "ALTER SYSTEM SET cluster_name='postgres4r2';"   # в auto.conf приехало 'postgres4r' от r1 — переписать
systemctl restart postgresql@18-main
# Каскадный basebackup со standby = 5:47, но CPU 9% — почти всё ожидание чекпойнта апстрима (помог ручной CHECKPOINT на r1).

### Проверка ###
# мастер: pg_stat_replication → видит только postgres4r (после каскада)
# r1:     pg_stat_replication → postgres4r2 (async), pg_replication_slots → slot_cascade active
