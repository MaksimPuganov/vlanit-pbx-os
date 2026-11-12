# Спецификация: меры безопасности (1.2)

Статус: **реализовано** (1.2.0, подтверждено 3 проверками агента на 1.2.1).

## 0. As-built

- fail2ban: бэкенд **`systemd`** (чтение journald), а не nftables — в системе
  нет rsyslog, `/var/log/auth.log` не существует. Джейл `[sshd]`
  (`/etc/fail2ban/jail.d/vlanit-sshd.conf`): maxretry 5, bantime 1h.
- Контроль стандартного пароля MikoPBX — в `vlanit-firstboot` (после старта
  контейнера): при пустом `WEB_ADMIN_PASSWORD` пробуется логин admin/admin
  через API с localhost; при успехе — предупреждение в журнал и MOTD.
  Автоматическая смена пароля не выполняется (конфликтует с env-provisioning).

## 1. unattended-upgrades

- Пакет `unattended-upgrades` в Golden Image.
- Конфиг `/etc/apt/apt.conf.d/20vlanit-auto-upgrades`:
  security-обновления Debian только; origins: `Debian-Security`, `Debian trixie-security`.
- Автоматический ребут — отключён (`Automatic-Reboot "false"`): устройство —
  телефония, ребут решает админ.
- Работает только при наличии интернета; офлайн-установка не затрагивается.

## 2. Запрет root по SSH

- `/etc/ssh/sshd_config.d/01-vlanit.conf`:
  `PermitRootLogin no`, `PasswordAuthentication yes` (ключи — позже),
  `MaxAuthTries 5`.
- Применяется ко всем новым установкам; SSH выключен — конфиг всё равно пишется.

## 3. Host fail2ban для SSH

- Пакет `fail2ban` в Golden Image; джейл `[sshd]`: `maxretry = 5`,
  `bantime = 1h` (после 5 неверных паролей блок IP на час).
- Бэкенд: nftables (штатный для trixie). Конфликта с fail2ban внутри
  контейнера MikoPBX нет: там своя сеть в контейнере; host-джейл видит
  только host-трафик.
- Служба включена по умолчанию.

## 4. Контроль стандартного пароля АТС

- В `vlanit-firstboot` (после старта контейнера): если `WEB_ADMIN_PASSWORD`
  в quadlet пуст/отсутствует — попытка API-проверки логина `admin/admin`
  (localhost bypass); при успехе — предупреждение в журнал и MOTD:
  «Веб-админ MikoPBX использует стандартный пароль — смените: https://<IP>».
- Не блокируем и не меняем сами: MikoPBX перезаписывает пароль из env
  при каждом старте, самостоятельная смена конфликтует с provisioning.

## 5. Критерии приёмки

- С 5 неверными паролями SSH IP блокируется (`fail2ban-client status sshd`).
- root по SSH отклонён, админ-пользователь входит.
- Автообновления security работают (проверка dry-run в тесте-агенте:
  `unattended-upgrades --dry-run` не падает).
- Предупреждение о стандартном пароле появляется в журнале при пустом
  `WEB_ADMIN_PASSWORD`.
