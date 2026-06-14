#!/bin/bash
# Время восстановления после kill -9 при разных checkpoint/full_page_writes. Запуск: sudo bash recovery_all.sh
PGB=/usr/lib/postgresql/18/bin/pgbench
LOG=/var/log/postgresql/postgresql-18-main.log
test_one() {
  local name="$1" ct="$2" mws="$3" fpw="$4"
  sudo -u postgres psql -q -c "ALTER SYSTEM SET checkpoint_timeout='$ct';" -c "ALTER SYSTEM SET max_wal_size='$mws';" -c "ALTER SYSTEM SET full_page_writes='$fpw';" -c "SELECT pg_reload_conf();" >/dev/null
  sudo -u postgres psql -q -d thai -c "CHECKPOINT;" >/dev/null
  sudo -u postgres $PGB -c 8 -j 4 -T 180 -n -U postgres thai >/dev/null 2>&1
  local wal=$(du -sh /var/lib/postgresql/18/main/pg_wal | cut -f1)
  pkill -9 -u postgres postgres; sleep 3
  systemctl start postgresql@18-main; sleep 8
  local rec=$(grep "redo done" $LOG | tail -1 | grep -oE 'elapsed: [0-9.]+ s')
  echo "$name | ckpt=$ct max_wal=$mws fpw=$fpw | WAL_dir=$wal | recovery $rec"
}
test_one TEST1 30min 10GB on
test_one TEST2 1min 1GB off
test_one TEST3 1min 1GB on
sudo -u postgres psql -q -c "ALTER SYSTEM SET checkpoint_timeout='15min';" -c "ALTER SYSTEM SET max_wal_size='1GB';" -c "ALTER SYSTEM SET full_page_writes='on';" -c "SELECT pg_reload_conf();" >/dev/null
echo DONE
