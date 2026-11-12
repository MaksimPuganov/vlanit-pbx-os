# Публикация CI-workflow (требуется scope `workflow`)

Файл `.github/workflows/build-iso.yml` собран и проверен локально, но в репозиторий
его может отправить только токен GitHub со scope **`workflow`** (ограничение GitHub
для OAuth-приложений: без этого scope пуш workflow-файлов отклоняется с ошибкой
`refusing to allow an OAuth App to create or update workflow ...`).

## Шаги (5 минут)

```bash
# 1. Обновить авторизацию gh, добавив scope workflow
gh auth refresh -h github.com -s workflow
# (откроется браузер — подтвердить)

# 2. Проверить, что scope появился
gh auth status
# в списке scopes должно быть: 'gist', 'read:org', 'repo', 'workflow'

# 3. Закоммитить и запушить workflow
cd vlanit-pbx-os   # клон репозитория vlanit-com/vlanit-pbx-os
mkdir -p .github/workflows
# скопировать build-iso.yml (содержимое — в конце этого документа)
git add .github/workflows/build-iso.yml
git commit -m "ci: сборка ISO по кнопке (workflow_dispatch) + публикация релиза"
git push
```

## Что делает workflow

`.github/workflows/build-iso.yml`:

- **Триггер**: вручную, кнопка «Run workflow» в разделе Actions
  (параметр `release`: опубликовать релиз после сборки — да/нет).
- **Шаги**: скачивание payload MikoPBX с проверкой digest → `make iso`
  (сборка в Docker-контейнере внутри runner'а) → либо артефакт к запуску,
  либо автоматический `gh release create v<version>`.

Требований к секретам нет: образ MikoPBX публичный, релиз публикуется
через `GITHUB_TOKEN` раннера.

## Содержимое .github/workflows/build-iso.yml

```yaml
# Сборка ISO VLANit PBX OS (запуск вручную — workflow_dispatch).
name: build-iso

on:
  workflow_dispatch:
    inputs:
      release:
        description: "Опубликовать релиз v<version> после сборки"
        type: boolean
        default: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Payload MikoPBX (pull + verify digest)
        run: bash scripts/pull-mikopbx.sh

      - name: Сборка ISO
        run: make iso

      - name: Артефакт ISO
        if: ${{ !inputs.release }}
        uses: actions/upload-artifact@v4
        with:
          name: vlanit-pbx-iso
          path: |
            dist/*.iso
            dist/*.iso.sha256
          retention-days: 14

      - name: Публикация релиза
        if: ${{ inputs.release }}
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VER=$(grep -oP 'version:\s*"\K[0-9.]+' config/build.yaml | head -1)
          gh release create "v${VER}" dist/*.iso dist/*.iso.sha256 \
            --title "VLANit PBX OS ${VER}" \
            --generate-notes
```

## Если что-то пошло не так

- `gh auth refresh` просит пароль/браузер — нормально, это единственный
  интерактивный шаг.
- Пуш всё ещё отклоняется — проверить `gh auth status` (scope `workflow`
  должен быть у активного аккаунта) и что пуш выполняется в
  `vlanit-com/vlanit-pbx-os` от пользователя с правом записи.
- После пуша workflow появится в GitHub → Actions → «build-iso» → Run workflow.
