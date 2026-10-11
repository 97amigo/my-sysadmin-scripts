#!/usr/bin/env bash
# script.sh — сборщик логов: фильтрация событий по ключевым словам и отчёт
# Использование: ./script.sh [-k "слово1|слово2"] [-o отчёт] [-n N]

set -eu   # без pipefail: иначе "sort | head" может завершить скрипт из-за SIGPIPE

LOG_FILE=""
KEYWORDS="error|fail|warning|critical|denied|refused|invalid|panic"
OUT="report.txt"
TAIL_N=20

usage() {
    cat <<EOF
Использование: $0 [-k "ключ1|ключ2"] [-o отчёт] [-n N]
  Источник выбирается сам: /var/log/syslog → /var/log/auth.log → journalctl
  -k  ключевые слова через | (по умолчанию: $KEYWORDS)
  -o  файл отчёта (по умолчанию: $OUT)
  -n  сколько последних событий показать (по умолчанию: $TAIL_N)
EOF
}

while getopts "k:o:n:h" opt; do
    case $opt in
        k) KEYWORDS="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        n) TAIL_N="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

TMP=$(mktemp); MATCHED=$(mktemp)
trap 'rm -f "$TMP" "$MATCHED"' EXIT

# 1. Выбор источника
for f in /var/log/syslog /var/log/auth.log; do
    [[ -r "$f" ]] && { LOG_FILE="$f"; break; }
done

if [[ -n "$LOG_FILE" ]]; then
    SOURCE="$LOG_FILE"
    cat "$LOG_FILE" > "$TMP"
elif command -v journalctl >/dev/null; then
    SOURCE="journalctl (последние 50000 записей)"
    journalctl --no-pager -o short -n 50000 > "$TMP" 2>/dev/null
else
    echo "Ошибка: не найден ни /var/log/syslog, ни /var/log/auth.log, ни journalctl" >&2
    exit 3
fi

# 2. Фильтрация
grep -iE -- "$KEYWORDS" "$TMP" > "$MATCHED" || true

TOTAL=$(wc -l < "$TMP")
FOUND=$(wc -l < "$MATCHED")
PERCENT=$(awk -v m="$FOUND" -v t="$TOTAL" 'BEGIN { printf "%.1f", t ? m*100/t : 0 }')

# время записи: поддерживаются оба формата ("Oct 11 12:00:00" и "2026-10-11T12:00:00")
ts()   { awk '{ if ($1 ~ /^[0-9][0-9][0-9][0-9]-/) print $1; else print $1" "$2" "$3 }'; }
# имя процесса: "sshd[123]:" → "sshd"
proc() { awk '{ p = ($1 ~ /^[0-9][0-9][0-9][0-9]-/) ? $3 : $5; sub(/\[.*/, "", p); sub(/:$/, "", p); print p }'; }
line() { printf '=%.0s' {1..70}; echo; }
none() { [[ -s "$1" ]] || echo "  (нет данных)"; }

# количество совпадений по каждому ключевому слову
IFS='|' read -ra KW <<< "$KEYWORDS"
declare -a CNT; MAX=1
for i in "${!KW[@]}"; do
    CNT[i]=$(grep -ic -- "${KW[i]}" "$MATCHED" || true)
    (( CNT[i] > MAX )) && MAX=${CNT[i]}
done

# 3. Отчёт
{
    printf '\xEF\xBB\xBF'   # BOM — чтобы на Mac/Windows кириллица открывалась правильно
    line
    echo "  ОТЧЁТ СБОРЩИКА ЛОГОВ"
    line
    echo "Дата отчёта:     $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Хост:            $(hostname)"
    echo "Пользователь:    $(whoami)"
    echo "Источник:        $SOURCE"
    echo "Период:          $(head -1 "$TMP" | ts)  —  $(tail -1 "$TMP" | ts)"
    echo "Ключевые слова:  $KEYWORDS"
    echo

    echo "1. ОБЩАЯ СТАТИСТИКА"; line
    printf "  Всего строк в логе:     %d\n" "$TOTAL"
    printf "  Найдено событий:        %d (%s%%)\n" "$FOUND" "$PERCENT"
    echo

    echo "2. СОБЫТИЯ ПО КЛЮЧЕВЫМ СЛОВАМ"; line
    for i in "${!KW[@]}"; do
        bar=$(( CNT[i] * 40 / MAX ))
        printf "  %-12s %7d  %s\n" "${KW[i]}" "${CNT[i]}" "$(printf '#%.0s' $(seq 1 $bar) 2>/dev/null | head -c $bar)"
    done
    echo

    echo "3. ТОП-10 ПРОЦЕССОВ С СОБЫТИЯМИ"; line
    proc < "$MATCHED" | sort | uniq -c | sort -rn | head -10 | awk '{ printf "  %7d  %s\n", $1, $2 }'
    none "$MATCHED"
    echo

    echo "4. ПОСЛЕДНИЕ $TAIL_N СОБЫТИЙ"; line
    tail -n "$TAIL_N" "$MATCHED" | sed 's/^/  /'
    none "$MATCHED"
    echo
    line
    echo "  Конец отчёта"
    line
} > "$OUT"

echo "Готово: проанализировано $TOTAL строк, найдено $FOUND событий ($PERCENT%)."
echo "Отчёт: $(realpath "$OUT")"
