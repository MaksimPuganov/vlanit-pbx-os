#!/usr/bin/env bash
# scripts/gpg-release-common.sh — общий префикс GPG-подписи релизными ключом.
# Источник: sign-release.sh (ISO) и build-update-package.sh (OTA-пакеты).
# Вызывающий скрипт: source этот файл, затем gpg_release_sign <файл> (подпись
# -> <файл>.asc рядом).
set -Eeuo pipefail

export GNUPGHOME="${GNUPGHOME:-$HOME/.vlanit-release-gnupg}"
# CI: приватный ключ приезжает из секрета в стандартный GNUPGHOME
if [ -n "${RELEASE_GPG_PRIVATE_KEY:-}" ] && [ ! -d "$GNUPGHOME/private-keys-v1.d" ]; then
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    echo "$RELEASE_GPG_PRIVATE_KEY" | gpg --batch --import
fi

[ -d "$GNUPGHOME" ] || {
    echo "gpg-release: приватный ключ релиза не найден (GNUPGHOME=$GNUPGHOME)" >&2
    echo "  локально: GNUPGHOME=\$HOME/.vlanit-release-gnupg" >&2
    echo "  CI: задайте секрет RELEASE_GPG_PRIVATE_KEY" >&2
    exit 1
}

# gpg_release_sign <файл> — detached ascii-armored подпись -> <файл>.asc
# (ключ без passphrase — batch-подпись)
gpg_release_sign() {
    gpg --batch --yes --armor --detach-sign -o "$1.asc" "$1"
}
