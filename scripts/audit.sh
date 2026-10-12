#!/usr/bin/env bash
# Аудит конфигурации devops-vm (ПР № 5).
# Запуск на сервере: bash audit.sh; код возврата 0 — все проверки пройдены, 1 — есть нарушения.
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
SSHD_T="$(sudo sshd -T)"
check "Вход от имени root запрещён"        "no"  "$(awk '/^permitrootlogin/{print $2}' <<<"$SSHD_T")"
check "Парольная аутентификация отключена" "no"  "$(awk '/^passwordauthentication/{print $2}' <<<"$SSHD_T")"

# TODO 1: значение параметра port отлично от 22
SSH_PORT="$(awk '/^port /{print $2}' <<<"$SSHD_T")"
check "Порт SSH отличен от 22 (сейчас: $SSH_PORT)" "yes" "$([[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]] && echo yes || echo no)"

# TODO 2: значение параметра maxauthtries равно 3
check "Ограничение попыток входа MaxAuthTries = 3" "3" "$(awk '/^maxauthtries/{print $2}' <<<"$SSHD_T")"

echo "[2] Межсетевой экран"
UFW_V="$(sudo ufw status verbose)"
check "Межсетевой экран активен" "active" "$(awk '/^Status:/{print $2}' <<<"$UFW_V")"

# TODO 3: политика по умолчанию для входящего трафика равна deny
#         строка вида: Default: deny (incoming), allow (outgoing), disabled (routed)
check "Политика по умолчанию для входящего трафика — deny" "deny" \
      "$(grep '^Default:' <<<"$UFW_V" | grep -o '[a-z]* (incoming)' | awk '{print $1}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
