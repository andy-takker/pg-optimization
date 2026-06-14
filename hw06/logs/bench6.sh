#!/bin/bash
# Матрица производительности: 6 конфигов через ALTER SYSTEM + reload (без рестарта).
PGB=/usr/lib/postgresql/18/bin/pgbench
DB=thai
OUT=/var/lib/postgresql/hw06_matrix.csv
echo "config,sync_commit,fpw,wal_compression,ckpt_timeout,max_wal_size,write_tps,read_tps,wal_mb" > $OUT
run() {
  local name="$1" sc="$2" fpw="$3" comp="$4" ct="$5" mws="$6"
  psql -q -c "ALTER SYSTEM SET synchronous_commit='$sc';" \
          -c "ALTER SYSTEM SET full_page_writes='$fpw';" \
          -c "ALTER SYSTEM SET wal_compression='$comp';" \
          -c "ALTER SYSTEM SET checkpoint_timeout='$ct';" \
          -c "ALTER SYSTEM SET max_wal_size='$mws';" \
          -c "SELECT pg_reload_conf();" >/dev/null
  sleep 2; psql -q -c "CHECKPOINT;" >/dev/null
  local s=$(psql -tAc "SELECT pg_current_wal_lsn();")
  local wtps=$($PGB -c 8 -j 4 -T 60 -n -U postgres $DB 2>/dev/null | grep -oP 'tps = \K[0-9.]+' | head -1)
  local e=$(psql -tAc "SELECT pg_current_wal_lsn();")
  local wal=$(psql -tAc "SELECT round(pg_wal_lsn_diff('$e','$s')/1048576.0,1);")
  psql -q -c "CHECKPOINT;" >/dev/null
  local rtps=$($PGB -c 8 -j 4 -T 30 -n -f /var/lib/postgresql/workload.sql -U postgres $DB 2>/dev/null | grep -oP 'tps = \K[0-9.]+' | head -1)
  echo "$name,$sc,$fpw,$comp,$ct,$mws,$wtps,$rtps,$wal" | tee -a $OUT
}
run A on  on  on  15min 1GB
run B off on  on  15min 1GB
run C on  off on  15min 1GB
run D on  on  off 15min 1GB
run E on  on  on  1min  256MB
run F on  on  on  30min 10GB
psql -q -c "ALTER SYSTEM SET synchronous_commit='on';" -c "ALTER SYSTEM SET full_page_writes='on';" -c "ALTER SYSTEM SET wal_compression='on';" -c "ALTER SYSTEM SET checkpoint_timeout='15min';" -c "ALTER SYSTEM SET max_wal_size='1GB';" -c "SELECT pg_reload_conf();" >/dev/null
echo "DONE -> $OUT"
