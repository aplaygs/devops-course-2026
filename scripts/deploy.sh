#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
# Коды возврата: 0 — ресурс доставлен и доступен (или выведен план при --dry-run), 1 — ошибка.
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

die() { echo "deploy: $*" >&2; exit 1; }

# 1. Разбор аргумента --dry-run
DRY_RUN=""
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *)         die "неизвестный аргумент '$1'. Использование: scripts/deploy.sh [--dry-run]" ;;
esac

cd "$REPO_ROOT"   # требование 2: одинаковое поведение из любого каталога репозитория

# 2. Проверки по требованиям 4 и 5
[[ -f "${LOCAL_DIR}index.html" ]] \
    || die "нет файла site/index.html — доставка отменена (--delete удалил бы главную страницу)"

# изменения в отслеживаемых файлах (в рабочей копии и в индексе) и неотслеживаемые файлы в site/
if [[ -n "$(git status --porcelain --untracked-files=no)" || -n "$(git status --porcelain -- site/)" ]]; then
    git status --short >&2
    die "есть незафиксированные изменения — зафиксируйте их перед деплоем"
fi

COMMIT="$(git rev-parse --short HEAD)"

# 3. Синхронизация: точная копия site/ с правами 755/644, одно SSH-соединение без запроса пароля
echo "Доставка коммита ${COMMIT} на ${REMOTE}:${REMOTE_DIR} ${DRY_RUN}"
rsync -az --itemize-changes --delete --chmod=D755,F644 ${DRY_RUN} \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" \
    || die "ошибка rsync (код $?)"

# 4. При --dry-run — завершение без проверки доступности
if [[ -n "$DRY_RUN" ]]; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
curl -fsS --cacert "$CA_CERT" --max-time 10 -o /dev/null "$SITE_URL/" \
    || die "ресурс ${SITE_URL} недоступен после доставки"

echo "Готово: ${SITE_URL} обслуживает коммит ${COMMIT}"
