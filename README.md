А — Сборщик логов. Скрипт читает /var/log/syslog (или /var/log/auth.log), фильтрует события по ключевым словам, формирует отчёт в файл report.txt(по-умолчанию).

Использование: ./script.sh [-k "ключ1|ключ2"] [-o отчёт] [-n N]
  Источник выбирается сам: /var/log/syslog → /var/log/auth.log → journalctl
  -k  ключевые слова через | (по умолчанию: error|fail|warning|critical|denied|refused|invalid|panic)
  -o  файл отчёта (по умолчанию: report.txt)
  -n  сколько последних событий показать (по умолчанию: 20)

Файл sample_output.txt получен командой "./script.sh -k "info|warning|fail" -n 50 -o sample_output.txt"
