# Исследование MikoPBX для VLANit PBX OS

Дата исследования: 2026-11-11
Исследовал: официальную документацию docs.mikopbx.com, исходный код образа
`mikopbx/mikopbx:2026.6.99-amd64` (файлы внутри контейнера), Docker Hub API.

## 1. Контейнерные образы и версии

Источники:
- Docker Hub: `mikopbx/mikopbx` (multi-arch manifest, включая `-amd64` и `-arm64` теги).
- GHCR: `ghcr.io/mikopbx/mikopbx` (используется в примерах официальной документации).
- Docker Hub API (проверено 2026-11-11): стабильный тег `2026.6.99`, `latest` → `2026.6.99`.
  Дев-теги `2026.6.102-dev`, `2026.6.98-dev` и др.

Выбранный образ для VLANit PBX OS 1.0:

```
mikopbx/mikopbx:2026.6.99-amd64
digest: sha256:6489e2a72ee6c670383ce7f61e21ad419880193ecad964d93e91596256c1c4b0
размер: 597924112 байт (~570 MiB), linux/amd64
```

`latest` не используется как фиксация версии — только конкретный тег + digest
в `config/release-manifest.yaml`.

## 2. Требования к запуску контейнера

Источник: [Running MikoPBX in a container](https://docs.mikopbx.com/mikopbx/english/setup/docker/running-mikopbx-in-container)
(проверено 2026-11-11), примеры сообщества (CSDN, Oduist) согласуются.

Подтверждённые параметры запуска:

| Параметр | Значение | Комментарий |
|---|---|---|
| Сеть | `--net=host` (host network) | Обязательно: SIP/RTP, fail2ban, iptables внутри контейнера. NAT не используется. |
| Capabilities | `NET_ADMIN` | Необходимо для fail2ban и iptables (proactive protection). Без него АТС работает, но без авто-блокировок. |
| Privileged | не нужен для базовой работы | Требуется только для модуля «Backup» (не входит в v1). |
| Volumes | `/cf` и `/storage` | Конфигурация и записи разговоров — persistent. |
| Пользователь данных | `ID_WWW_USER` / `ID_WWW_GROUP` | UID/GID владельца каталогов cf/storage (не root). |
| Restart | always / systemd | Через systemd Quadlet (`Restart=always`). |

### Persistent volumes (подтверждено документацией и практикой Docker)

- `/cf` — конфигурация АТС (SQLite БД, настройки). Разворачивается при первом старте.
- `/storage` — записи разговоров, временные файлы, логи.
Хост-каталоги по документации: `/var/spool/mikopbx/cf`, `/var/spool/mikopbx/storage`.

### Расположение данных внутри контейнера

- Приложение: `/offload/rootfs/usr/www` (исходники PHP, включая `src/Core/System/`).
- Точка входа: `/sbin/docker-entrypoint` (shell), запускает
  `php -f /offload/rootfs/usr/www/src/Core/System/ContainerEntrypoint.php`.
- Сигналы: entrypoint обрабатывает SIGINT/SIGTERM/SIGHUP/SIGQUIT → cleanup
  (`freestorage`, `freeupoffload`). Корректная остановка контейнера поддерживается
  (systemd `TimeoutStopSec` должен быть ≥ 10 сек).

## 3. Переменные окружения

Документированные ([источник](https://docs.mikopbx.com/mikopbx/english/setup/docker/running-mikopbx-in-container)):

`SSH_PORT`(22), `WEB_PORT`(80), `WEB_HTTPS_PORT`(443), `SIP_PORT`(5060),
`TLS_PORT`(5061), `RTP_PORT_FROM`(10000), `RTP_PORT_TO`(10800), `IAX_PORT`(4569),
`AMI_PORT`(5038), `AJAM_PORT`(8088), `AJAM_PORT_TLS`(8089), `BEANSTALK_PORT`(4229),
`REDIS_PORT`(6379), `GNATS_PORT`(4223), `ID_WWW_USER`, `ID_WWW_GROUP`,
`WEB_ADMIN_LOGIN`, `WEB_ADMIN_PASSWORD`.

Подтверждено исходным кодом образа 2026.6.99
(`/offload/rootfs/usr/www/src/Core/System/CloudProvisioning/DockerCloud.php`,
`ProvisioningConfig.php` — класс `DockerCloud`, проверено 2026-11-11):

- Провайдер `DockerCloud` применяет переменные окружения **при каждом старте
  контейнера** (12-factor подход), результат пишется в БД настроек (`PbxSettings`).
- Маппинг: `PBX_NAME` → hostname; `WEB_ADMIN_PASSWORD` → пароль веб-админа;
  `SSH_AUTHORIZED_KEYS` → SSH-ключи; `ENABLE_USE_NAT` → топология сети;
  `EXTERNAL_SIP_IP_ADDR` / `EXTERNAL_SIP_HOST_NAME` → внешний адрес SIP;
  **любая другая константа `PbxSettings` → прямое обновление БД**.
- Порты (`BEANSTALK_PORT`, `REDIS_PORT`, `GNATS_PORT`, `GNATS_HTTP_PORT`)
  применяются до старта Redis и пишутся в `/etc/inc/mikopbx-settings.json`.
- Валидация: hostname по RFC 1123, лимиты длины строк (1024), SSH-ключи (65536).

**Вывод для provisioning**: первичную настройку MikoPBX (имя, пароль админа,
сетевые параметры) можно задавать декларативно через переменные окружения
контейнера — они применяются идемпотентно при каждом старте и сохраняются в БД,
т.е. конфигурация переживает обновление образа контейнера.

## 4. REST API

Источник: [PBXCoreREST v3](https://docs.mikopbx.com/mikopbx-development/internal-structure/api/rest-api)
(проверено 2026-11-11).

- Базовый путь: `/pbxcore/api/v3/{resource}`; стандартный CRUD + custom methods `:{method}`.
- Аутентификация: JWT (`POST /pbxcore/api/v3/auth:login` → `data.accessToken`,
  TTL 15 мин; refresh 30 дней) или API-ключ (64 hex, заголовок
  `Authorization: Bearer <key>` или `X-Api-Key`), либо localhost bypass (запросы
  с 127.0.0.1 без токена).
- Веб-кабинет: `POST /admin-cabinet/session/start` (form: login/password) —
  легаси-сессия, для скриптов предпочтительнее v3 JWT.
- Обработка асинхронная (Redis-очередь), коды 200/201/401/403/404/409/422/503.
- OpenAPI генерируется из атрибутов контроллеров.

Для VLANit PBX OS 1.0 API подтверждён как рабочий механизм, но полноценное
прикладное provisioning через API (транки, маршруты) **не реализуется** до
подтверждения конкретных ресурсов на живой системе. Базовые параметры задаются
через переменные окружения (п. 3), проверка результата — HTTP-запросы к
веб-интерфейсу и API-логин с localhost.

## 5. Готовность приложения и проверки

Документированный признак готовности (лог контейнера, проверено по
документации):

```
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
|               All services are fully loaded welcome                |
|                         MikoPBX 2026.1.223                         |
...
| Web Interface Access  https://<IP>   Login: admin / Password: admin
```

VLANit health-check использует:
1. `systemctl is-active` для quadlet-службы контейнера.
2. Лог контейнера: баннер «All services are fully loaded welcome».
3. HTTP(S) GET к веб-порту (ожидание 200/302) — не только факт запуска процесса.
4. `POST /pbxcore/api/v3/auth:login` с localhost для контрольной проверки API.

## 6. Требования к ОС и железу

- Хост: Linux kernel 5+, тестировано на Debian 11 / Ubuntu 21.04 / 22.04
  ([источник](https://docs.mikopbx.com/mikopbx/english/setup/docker)).
  Debian 13 (kernel 6.x) — совместим по требованию «Linux 5+»; фактическая
  проверка выполняется в QEMU (см. docs/testing.md).
- Минимум по [официальным требованиям](https://docs.mikopbx.com/mikopbx/english/readme/system-requirements):
  x86-64 CPU, 2 GB RAM, 800 MB под систему, 50+ GB под записи разговоров.
  Установщик VLANit предупреждает при RAM < 2 GB и диске < 64 GB, но не
  блокирует установку (значения предварительные, отмечены как таковые).

## 7. Podman

Подтверждений/ограничений официальной поддержки Podman у MikoPBX не найдено
(документация описывает Docker). Ограничение зафиксировано.
Ожидаемая совместимость: rootful Podman + `--network host` + `--cap-add NET_ADMIN`
(аналог `docker run`). Требования к namespaces — стандартные; образ не требует
специальных устройств (DAHDI опционален и не используется).
SELinux на Debian отсутствует; AppArmor не должен блокировать rootful-контейнер
с host network (проверяется в тестах). Точный набор флагов и работоспособность
fail2ban подтверждаются тестовым прогоном (docs/testing.md).

## 8. Сохранение конфигурации при обновлении образа

Конфигурация в `/cf` (БД SQLite + файлы настроек). Обновление контейнерного
образа не затрагивает примонтированные `/cf` и `/storage` — настройки
сохраняются. Дополнительно env-provisioning перенакладывает заявленные
параметры при каждом старте.

## 9. Что НЕ подтверждено (не используется в v1)

- Прямое редактирование БД или конфигов Asterisk — запрещено, не применяется.
- Внутренние эндпоинты v3 для SIP-объектов — будут исследованы на живой системе
  перед добавлением в PBX Provisioning.
- Модуль Backup (требует `--privileged`) — вне scope v1.
