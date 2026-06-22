-- hw09: запросы «отчёт по поездкам» (город от/до, мест всего, занято, заработок) на 60 млн строк

-- ============ НАИВНЫЙ (базлайн, декартов взрыв tickets × seat) ============
-- EXPLAIN: Merge Join ~2.4 млрд строк, cost 113.9M; EXPLAIN ANALYZE — таймаут >180 с
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.startdate AS depart_date,
       bf.city||', '||bf.name AS from_station,
       bt.city||', '||bt.name AS to_station,
       count(t.id) AS order_place, count(st.id) AS all_place,
       count(t.id)*max(s.price) AS revenue
FROM book.ride r
JOIN book.schedule s    ON r.fkschedule = s.id
JOIN book.busroute br   ON s.fkroute = br.id
JOIN book.busstation bf ON br.fkbusstationfrom = bf.id
JOIN book.busstation bt ON br.fkbusstationto   = bt.id
JOIN book.tickets t     ON t.fkride = r.id
JOIN book.seat st       ON st.fkbus = r.fkbus
GROUP BY r.id, r.startdate, bf.city||', '||bf.name, bt.city||', '||bt.name
ORDER BY r.startdate LIMIT 10;

-- ============ ОПТИМИЗИРОВАННЫЙ (раздельные агрегаты) ============
-- 43 с без индекса -> 12 с с индексом tickets(fkRide)
EXPLAIN (ANALYZE, BUFFERS)
WITH order_place AS (
    SELECT fkRide, count(*) AS order_place FROM book.tickets GROUP BY fkRide
),
all_place AS (
    SELECT fkbus, count(*) AS all_place FROM book.seat GROUP BY fkbus
)
SELECT r.id, r.startdate AS depart_date,
       bf.city||', '||bf.name AS from_station,
       bt.city||', '||bt.name AS to_station,
       ap.all_place, op.order_place,
       (op.order_place * s.price) AS revenue
FROM book.ride r
JOIN book.schedule s    ON r.fkschedule = s.id
JOIN book.busroute br   ON s.fkroute = br.id
JOIN book.busstation bf ON br.fkbusstationfrom = bf.id
JOIN book.busstation bt ON br.fkbusstationto   = bt.id
JOIN all_place ap       ON ap.fkbus  = r.fkbus
JOIN order_place op     ON op.fkRide = r.id
ORDER BY r.startdate LIMIT 10;

CREATE INDEX idx_tickets_fkride ON book.tickets(fkRide);  -- включает Index Only Scan

-- ============ ПРЕАГРЕГАТ (потолок, 0.18 мс) ============
CREATE MATERIALIZED VIEW book.mv_rides AS
WITH order_place AS (SELECT fkRide, count(*) AS order_place FROM book.tickets GROUP BY fkRide),
     all_place   AS (SELECT fkbus,  count(*) AS all_place   FROM book.seat   GROUP BY fkbus)
SELECT r.id, r.startdate AS depart_date,
       bf.city||', '||bf.name AS from_station, bt.city||', '||bt.name AS to_station,
       ap.all_place, op.order_place, (op.order_place * s.price) AS revenue
FROM book.ride r
JOIN book.schedule s ON r.fkschedule=s.id
JOIN book.busroute br ON s.fkroute=br.id
JOIN book.busstation bf ON br.fkbusstationfrom=bf.id
JOIN book.busstation bt ON br.fkbusstationto=bt.id
JOIN all_place ap ON ap.fkbus=r.fkbus
JOIN order_place op ON op.fkRide=r.id;
CREATE INDEX ON book.mv_rides(depart_date);
SELECT * FROM book.mv_rides ORDER BY depart_date LIMIT 10;   -- 0.18 мс
-- обновление: REFRESH MATERIALIZED VIEW [CONCURRENTLY] book.mv_rides;
