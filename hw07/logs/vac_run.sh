#!/bin/bash
# Прогон одного режима: сброс таблицы, фоновый семплер n_dead_tup, нагрузка update+delete с -P 5.
# Запуск: sudo -u postgres bash vac_run.sh <label>   (конфиг автовакуума задаётся ДО запуска)
LABEL="$1"
PGB=/usr/lib/postgresql/18/bin/pgbench
DB=bench
DIR=/var/lib/postgresql/hw07
mkdir -p $DIR
psql -d $DB -q -c "VACUUM FULL t;" -c "ANALYZE t;" -c "SELECT pg_stat_reset_single_table_counters('t'::regclass);" >/dev/null
SAMP=$DIR/${LABEL}_dead.csv
echo "t,n_dead,n_live,size_mb" > $SAMP
( for i in $(seq 1 60); do
    psql -d $DB -tAc "SELECT extract(epoch from now())::bigint||','||n_dead_tup||','||n_live_tup||','||round(pg_total_relation_size('t')/1048576.0,1) FROM pg_stat_user_tables WHERE relname='t';" >> $SAMP
    sleep 3
  done ) &
SPID=$!
$PGB -c 4 -j 4 -T 180 -P 5 -f /var/lib/postgresql/write.sql -n -U postgres $DB 2>&1 | grep -E '^progress:' | awk '{print $2","$4}' > $DIR/${LABEL}_tps.csv
kill $SPID 2>/dev/null
AV=$(psql -d $DB -tAc "SELECT autovacuum_count FROM pg_stat_user_tables WHERE relname='t';")
SZ=$(psql -d $DB -tAc "SELECT round(pg_total_relation_size('t')/1048576.0,1) FROM pg_stat_user_tables WHERE relname='t';")
echo "=== $LABEL: autovacuum_count=$AV, final_size=${SZ}MB ==="
awk -F, '{s+=$2; ss+=$2*$2; n++} END{m=s/n; sd=sqrt(ss/n-m*m); printf "TPS mean=%.1f stddev=%.1f CV=%.1f%%\n", m, sd, 100*sd/m}' $DIR/${LABEL}_tps.csv
