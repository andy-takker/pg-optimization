# hw07 — тюнинг автовакуума на профиле update+delete: добиться равномерной нагрузки
# Стенд: GCP e2-standard-4, pd-ssd 50GB, Ubuntu 24.04, PostgreSQL 18.4 (PGDG), конфиг курса.

### Таблица и наполнение ###
CREATE DATABASE bench;
CREATE TABLE t (id serial PRIMARY KEY, u uuid);
INSERT INTO t (u) SELECT gen_random_uuid() FROM generate_series(1,200000);

### Профиль нагрузки update+delete (write.sql) ###
# \set lo random(1, 200000)
# UPDATE t SET u = gen_random_uuid() WHERE id BETWEEN :lo AND :lo + 50;
# DELETE FROM t WHERE id IN (SELECT id FROM t ORDER BY id LIMIT 50);
# INSERT INTO t (u) SELECT gen_random_uuid() FROM generate_series(1,50);

### Прогон (vac_run.sh): VACUUM FULL+reset -> фоновый семплер n_dead_tup -> pgbench -P5 -T180 -c4 ###
sudo -u postgres bash vac_run.sh <label>

### Режим 1 — DEFAULT (пер-табличные настройки сброшены) ###
# autovacuum_vacuum_scale_factor=0.2, naptime=1min

### Режим 2 — RARE (автовакуум почти не запускается) ###
ALTER TABLE t SET (autovacuum_vacuum_scale_factor=50, autovacuum_vacuum_threshold=100000000,
                   autovacuum_analyze_scale_factor=50, autovacuum_vacuum_insert_scale_factor=50);

### Режим 3 — TUNED (частый автовакуум малыми порциями) ###
ALTER TABLE t RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold,
                     autovacuum_analyze_scale_factor, autovacuum_vacuum_insert_scale_factor);
ALTER TABLE t SET (autovacuum_vacuum_scale_factor=0.01, autovacuum_vacuum_threshold=100,
                   autovacuum_analyze_scale_factor=0.01);
ALTER SYSTEM SET autovacuum_max_workers=4;        -- рестарт
ALTER SYSTEM SET autovacuum_naptime='10s';
ALTER SYSTEM SET autovacuum_vacuum_cost_limit=2000;
sudo systemctl restart postgresql@18-main

### Уборка ###
gcloud compute instances delete postgres7 --zone=europe-west1-b

# ВАЖНО про метрику: профиль НЕ count-stable — под конкуренцией (4 клиента) DELETE ... ORDER BY id LIMIT 50
# удаляет <50 строк (клиенты бьются за младшие id), а INSERT всегда +50 -> таблица растёт по числу строк
# (tuned дошёл до ~7.3M живых строк). Поэтому абсолютный размер файла НЕ является чистой метрикой блоата.
# Валидные сигналы: стабильность TPS (CV) и динамика n_dead_tup.
