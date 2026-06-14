# pg-optimization

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791?logo=postgresql&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-4B%208GB-A22846?logo=raspberrypi&logoColor=white)
![GCP](https://img.shields.io/badge/GCP-e2--standard--4-4285F4?logo=googlecloud&logoColor=white)

Домашние задания курса по оптимизации и администрированию PostgreSQL: тюнинг ОС и СУБД, бенчмарки, пулинг соединений, файловые системы, бэкапы и репликация. Каждая работа — воспроизводимый эксперимент: стенд, методика, замеры (медианы из 3 прогонов), графики и выводы.

## Работы

| ДЗ | Тема | Стенд | Главный результат |
|---|---|---|---|
| [hw01](hw01/) | Первичная настройка ОС и PostgreSQL: бенчмарки и тюнинг | Raspberry Pi 4B | Отключение fsync: ×2.9 TPS на записи; тюнинг памяти: +17% на чтении |
| [hw02](hw02/) | Коннектинг: vanilla vs PgBouncer vs Odyssey vs HAProxy при 500+ коннектах | GCP e2-standard-4 | Пулер — не ускоритель: ваниль быстрее на быстрых запросах, но деградирует вдвое круче; оптимум пула ≈ 2×ядра |
| [hw03](hw03/) | ФС: секционирование по дням, секции на 3 дисках, COPY vs pgloader, ext4/xfs/btrfs | GCP + 3 диска | Pruning: ×49 по ключу, медленнее мимо ключа; COPY ×20 быстрее pgloader; разница ФС ≤15% |
| [hw04](hw04/) | Репликация: синхр./асинхр./каскад, 5 уровней синхронного коммита, hot_standby_feedback | GCP, 3 ВМ | Синхронность вдвое режет запись на `on`; каскад не грузит мастер; `2S_ALL` медленнее кворума |
| [hw05](hw05/) | Мониторинг: VictoriaMetrics + Grafana + postgres/node exporter + vmalert/Alertmanager | GCP, Docker | Стек собирается за минуты без суперюзера (`pg_monitor`); алерт на диск отработал; «нет алерта» ≠ «всё ок» |
| [hw06](hw06/) | Тюнинг WAL/checkpoint: производительность vs надёжность, восстановление, сжатие WAL | GCP e2-standard-4 | `synchronous_commit=off` +80% записи; редкий чекпойнт → дольше восстановление; сжатие WAL ×4.9 на заполненных страницах |
| [hw07](hw07/) | Тюнинг автовакуума на профиле update+delete: убираем пилу TPS | GCP e2-standard-4 | Дефолт = пила (CV 31%), отключение = деградация (CV 52%), частый автовакуум малыми порциями = ровно (CV 11%) и быстрее |

## Ключевые находки

| | |
|---|---|
| [![fsync](hw01/images/tpcb_tps.png)](hw01/) | [![пулеры](hw02/images/final_500.png)](hw02/) |
| **hw01:** цена fsync на медленном носителе — трёхкратная разница TPS | **hw02:** каждый хоп и каждый лишний серверный коннект стоят TPS |
| [![pruning](hw03/images/pruning.png)](hw03/) | [![кеши](hw03/images/cache_levels.png)](hw03/) |
| **hw03:** секционирование ускоряет только запросы по ключу | **hw03:** рестарт СУБД сбрасывает лишь первый из трёх уровней кеша |
| [![синхронный коммит](hw04/images/sync_levels.png)](hw04/) | [![hot_standby_feedback](hw04/images/hot_standby_feedback.png)](hw04/) |
| **hw04:** цена синхронности растёт `off→remote_apply`; ждать обе реплики дороже кворума | **hw04:** `hot_standby_feedback=on` спасает долгий запрос на реплике от вакуума мастера |
| [![мониторинг PG](hw05/images/grafana_postgres.png)](hw05/) | [![алерт на диск](hw05/images/vmalert_diskspacelow.png)](hw05/) |
| **hw05:** дашборд PostgreSQL под нагрузкой 25k TPS (VictoriaMetrics + Grafana) | **hw05:** алерт `DiskSpaceLow` сработал и доехал до Alertmanager |
| [![производительность vs WAL](hw06/images/perf_matrix.png)](hw06/) | [![сжатие WAL](hw06/images/wal_compression.png)](hw06/) |
| **hw06:** `synchronous_commit=off` +80% записи; `wal_compression` режет WAL ×4.9 | **hw06:** выгода сжатия WAL зависит от данных: ×4.9 на заполненных, ×1.1 на случайных |
| [![пила автовакуума](hw07/images/tps_over_time.png)](hw07/) | [![мёртвые строки](hw07/images/dead_tuples.png)](hw07/) |
| **hw07:** дефолтный автовакуум даёт пилу TPS; частый малыми порциями — ровную линию | **hw07:** `n_dead_tup` во времени: монотонный рост (rare) vs пила (default) vs коридор (tuned) |

## Стенды

- **Raspberry Pi 4B** (4×Cortex-A72, 8 ГБ, microSD) — узкое место IO: на нём эффекты fsync, чекпоинтов и WAL видны невооружённым глазом.
- **GCP e2-standard-4** (4 vCPU, 16 ГБ, pd-ssd) — повторяет лекционный стенд курса; для экспериментов с сотнями коннектов и пулерами.

## Инструментарий

[pgbench](https://www.postgresql.org/docs/current/pgbench.html) ·
[PgBouncer](https://www.pgbouncer.org/) ·
[Odyssey](https://github.com/yandex/odyssey) ·
[HAProxy](https://www.haproxy.org/) ·
учебная БД [«Тайские перевозки»](https://github.com/aeuge/postgres16book/tree/main/database) (~6 млн строк) ·
[pgconfigurator](https://pgconfigurator.cybertec.at/)

## Полезные материалы

- [PostgreSQL: Tuning Your Server](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server) — стартовый чеклист от сообщества
- [Kernel Resources](https://www.postgresql.org/docs/current/kernel-resources.html) — overcommit, OOM, huge pages
- [Non-Durable Settings](https://www.postgresql.org/docs/current/non-durability.html) — официальный список «скорость в обмен на надёжность»
- [В защиту swap'а](https://habr.com/ru/companies/flant/articles/348324/) — как на самом деле работает swappiness
- [How to SCRAM with pgBouncer](https://www.crunchydata.com/blog/pgbouncer-scram-authentication-postgresql) — аутентификация через пулер
