# hw05 — мониторинг PostgreSQL: VictoriaMetrics + Grafana + vmalert + Alertmanager (1 ВМ GCP, PG 18.4)

### ВМ + PostgreSQL + Docker ###
gcloud compute instances create postgres5 --zone=europe-west1-b --machine-type=e2-standard-4 \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=100GB --boot-disk-type=pd-ssd
# PG 18 (PGDG) + конфиг курса (shared_buffers 4GB, pg_stat_statements, track_io_timing, listen_addresses='*')
# Docker — официальным скриптом:
curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker $USER   # перелогиниться, чтобы группа docker применилась
# учебная БД:
wget https://storage.googleapis.com/thaibus/thai_small.tar.gz && tar -xf thai_small.tar.gz && psql < thai.sql   # book.tickets = 5 185 505

### Роль мониторинга (без суперюзера) ###
CREATE USER monitoring PASSWORD 'mon123';
GRANT pg_monitor TO monitoring;                 -- доступ к pg_stat_* без superuser
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- в БД thai
# pg_hba.conf:
#   host all monitoring 127.0.0.1/32 scram-sha-256
#   host all monitoring 172.16.0.0/12 scram-sha-256   (docker-сети)

### Стек ###
# docker-compose.yml + scrape.yml + alerts.yml + alertmanager.yml (в этой папке)
docker compose up -d            # 6 контейнеров: victoriametrics, node_exporter, postgres_exporter, vmalert, alertmanager, grafana
# postgres_exporter ходит в PG как monitoring через host.docker.internal (extra_hosts: host-gateway)

### Проверка, что метрики текут ###
curl -s localhost:9187/metrics | grep '^pg_up '                          # pg_up 1
curl -s 'http://localhost:8428/api/v1/query?query=up'                    # node=1, postgres=1
curl -s 'http://localhost:8428/api/v1/query?query=pg_stat_activity_count' # 24 серии
curl -s 'http://localhost:8428/api/v1/query?query=node_memory_MemAvailable_bytes' # 14901919744

### Grafana (через SSH-туннель: -L 3000 -L 8880 -L 9093) ###
# Data source: Prometheus, URL http://victoriametrics:8428
# Дашборды по ID: 1860 (Node Exporter Full), 9628 (PostgreSQL Database / postgres_exporter)

### Нагрузка ###
cat > ~/workload.sql << 'EOL'
\set r random(1, 5000000)
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets WHERE id = :r;
EOL
/usr/lib/postgresql/18/bin/pgbench -c 20 -j 4 -T 180 -f ~/workload.sql -n -U postgres thai
# Результат: tps = 25151.77, latency avg 0.795 ms, 4 526 397 транзакций, 0 ошибок

### Триггер алерта на диск (отдельная маленькая ФС, чтобы быстро и безопасно) ###
sudo fallocate -l 2G /demo.img && sudo mkfs.ext4 -F /demo.img
sudo mkdir -p /mnt/demo && sudo mount -o loop /demo.img /mnt/demo
sudo fallocate -l 1800M /mnt/demo/fill
df -h /mnt/demo     # /dev/loop3  2.0G  1.8G  28M  99%  /mnt/demo
# ГРАБЛИ: node_exporter стартовал ДО mount — новый loop-моунт не сразу попал в его mount-namespace.
# Лечение: docker compose restart node_exporter (перечитывает моунты хоста при старте).
# Через ~1 мин (интервал оценки vmalert) DiskSpaceLow -> firing -> Alertmanager.

### Уборка ###
gcloud compute instances delete postgres5 --zone=europe-west1-b
