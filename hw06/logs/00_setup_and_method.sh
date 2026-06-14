# hw06 — тюнинг shared_buffers/bgwriter/checkpoint/WAL: производительность vs надёжность
# Стенд: GCP e2-standard-4, pd-ssd 50GB, Ubuntu 24.04, PostgreSQL 18.4 (PGDG), конфиг курса.
# БД: thai_small (book.tickets = 5 185 505); таблица t(u uuid) и pgbench -i -s 50 для нагрузки.

### Бутстрап ###
# PG18 + конфиг курса (shared_buffers 4GB, pg_stat_statements, track_io_timing, wal_compression on)
wget https://storage.googleapis.com/thaibus/thai_small.tar.gz && tar -xf thai_small.tar.gz && psql < thai.sql
psql -d thai -c "CREATE EXTENSION pg_stat_statements; CREATE TABLE t(u uuid);"
pgbench -i -s 50 -U postgres thai            # pgbench_* для TPC-B write-нагрузки

### Рестарт под systemd ###
sudo systemctl restart postgresql@18-main    # для wal_level/shared_buffers; остальное — pg_reload_conf()

### Шаг 1: влияние wal_level на объём WAL (wal_level_test.sh) ###
# один набор операций (INSERT 1M + UPDATE 1M + DDL), 3 метода замера:
#   pg_wal_lsn_diff, sum(pg_stat_statements.wal_bytes), pg_waldump -z (Total combined)
# minimal требует max_wal_senders=0 (уже 0). Переключение wal_level — рестарт.

### Шаг 2: матрица производительности (bench6.sh) ###
# 6 конфигов A–F, все параметры через ALTER SYSTEM + pg_reload_conf() (без рестарта).
# write = pgbench TPC-B (-c8 -j4 -T60), read = SELECT по PK book.tickets (-T30), CHECKPOINT перед прогоном.
# WAL за прогон = pg_wal_lsn_diff(end,start).

### Шаг 3: время восстановления (recovery_all.sh) ###
# для каждого конфига: CHECKPOINT -> pgbench 180s -> pkill -9 postgres -> systemctl start -> grep 'redo done ... elapsed'

### Шаг 4: pg_test_fsync + сжатие WAL ###
/usr/lib/postgresql/18/bin/pg_test_fsync
# сжатие: для off/pglz/lz4/zstd — TRUNCATE+INSERT 1M uuid -> CHECKPOINT -> UPDATE all (FPI) -> WAL diff

### Уборка ###
gcloud compute instances delete postgres6 --zone=europe-west1-b
