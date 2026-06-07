-- ============ DDL секционирования ============
CREATE TABLE book.tickets_part (
    id        bigint NOT NULL,
    fkRide    int,
    fio       text,
    contact   jsonb,
    fkSeat    int,
    startDate date NOT NULL
) PARTITION BY RANGE (startDate);

-- генерация 100 дневных секций (выполнять с \gexec)
SELECT format(
  'CREATE TABLE book.tickets_p%s PARTITION OF book.tickets_part FOR VALUES FROM (%L) TO (%L);',
  to_char(d, 'YYYYMMDD'), d::date, d::date + 1)
FROM generate_series('2000-01-01'::date, '2000-04-09'::date, '1 day') d
\gexec

INSERT INTO book.tickets_part
SELECT t.id, t.fkRide, t.fio, t.contact, t.fkSeat, r.startDate
FROM book.tickets t JOIN book.ride r ON r.id = t.fkRide;

CREATE INDEX ON book.tickets_part (startDate, id);
VACUUM ANALYZE book.tickets_part;

-- ============ Табличные пространства ============
-- (диски: mkfs.ext4 /dev/sdb /dev/sdc; mount в /mnt/disk2 /mnt/disk3; chown postgres)
CREATE TABLESPACE ts_ssd LOCATION '/mnt/disk2/pgts';
CREATE TABLESPACE ts_hdd LOCATION '/mnt/disk3/pgts';

-- round-robin раскладка секций по дате % 3 (таблицы; для индексов то же с relkind='i')
SELECT format('ALTER TABLE book.%I SET TABLESPACE %s;', c.relname,
       (ARRAY['pg_default','ts_ssd','ts_hdd'])
       [1 + (to_date(substring(c.relname from 'tickets_p(\d{8})'), 'YYYYMMDD') - DATE '2000-01-01') % 3])
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'book' AND c.relname LIKE 'tickets_p2000%' AND c.relkind = 'r'
\gexec

-- контроль
SELECT coalesce(tablespace, 'pg_default') ts, count(*)
FROM pg_tables WHERE tablename LIKE 'tickets_p2000%' GROUP BY 1;

-- ============ Методика холодного замера ============
-- sudo pg_ctlcluster 18 main stop
-- sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
-- sudo pg_ctlcluster 18 main start
-- (рестарт PG без drop_caches сбрасывает только shared_buffers, page cache ОС остаётся!)

-- ============ Тестовые запросы ============
-- A1 (1 секция):
SELECT count(*) FROM book.tickets_part WHERE startDate = '2000-02-01';
-- A2 (10 секций):
SELECT count(*) FROM book.tickets_part WHERE startDate >= '2000-02-01' AND startDate < '2000-02-11';
-- A3 (все 100, ключа нет в WHERE):
SELECT count(*) FROM book.tickets_part WHERE fio LIKE 'IVANOV%';
-- Эквиваленты для обычной таблицы: JOIN book.ride r ON r.id = t.fkRide + те же условия по r.startDate
