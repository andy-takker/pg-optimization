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

## Ключевые находки

| | |
|---|---|
| [![fsync](hw01/images/tpcb_tps.png)](hw01/) | [![пулеры](hw02/images/final_500.png)](hw02/) |
| **hw01:** цена fsync на медленном носителе — трёхкратная разница TPS | **hw02:** каждый хоп и каждый лишний серверный коннект стоят TPS |
| [![pruning](hw03/images/pruning.png)](hw03/) | [![кеши](hw03/images/cache_levels.png)](hw03/) |
| **hw03:** секционирование ускоряет только запросы по ключу | **hw03:** рестарт СУБД сбрасывает лишь первый из трёх уровней кеша |

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
