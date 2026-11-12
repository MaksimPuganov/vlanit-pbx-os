# Спецификация: CI-сборка ISO (1.2)

Статус: принято. Приоритет: низкий.

## 1. Workflow

`.github/workflows/build-iso.yml`:

- Триггер: `workflow_dispatch` (кнопка «Run workflow») с опциональным input
  `mikopbx_tag` (по умолчанию зашитый в `config/build.yaml`).
- Runner: `ubuntu-latest`.

## 2. Шаги

1. Checkout.
2. Скачивание payload MikoPBX: `scripts/pull-mikopbx.sh` (docker pull →
   sha256-проверка digest) — секреты не нужны (публичный образ).
3. Сборка: `make iso` (build-контейнер внутри runner).
4. Публикация: `gh release create` при dispatch с input `release=true`,
   иначе артефакт `dist/*.iso` прикреплён к запуску workflow
   (retention 14 дней).

## 3. Не входит (отдельные задачи)

- Запуск QEMU-тестов в CI (нужен KVM-доступ в runner'ах; GitHub предоставляет
  nested KVM только на определённых тарифах — отдельное исследование).
- Подпись релизов GPG (ключ релиза появится при внедрении OTA-цепочки).

## 4. Критерии приёмки

- Запуск по кнопке на чистом runner'е завершается ISO;
- digest образа MikoPBX совпадает с манифестом;
- время сборки ≤ 30 минут.
