#!/bin/bash
set -e
Q="/c/Users/mdpac/AppData/Local/Temp/claude/D--OJT-PM-Mock-Up/bf248e35-ad14-4ffa-82a3-1230705c2140/scratchpad/pg/pgsql/bin/psql.exe -X -h 127.0.0.1 -p 55433 -U postgres -d load -v ON_ERROR_STOP=1 -q -tA"
M() { "/c/Users/mdpac/AppData/Local/Temp/claude/D--OJT-PM-Mock-Up/bf248e35-ad14-4ffa-82a3-1230705c2140/scratchpad/pg/pgsql/bin/vacuumdb.exe" -h 127.0.0.1 -p 55433 -U postgres -d load -z -q; cd "D:/OJT_PM/Mock Up/appsmith/tools/beban"; PSQL="/c/Users/mdpac/AppData/Local/Temp/claude/D--OJT-PM-Mock-Up/bf248e35-ad14-4ffa-82a3-1230705c2140/scratchpad/pg/pgsql/bin/psql.exe" python -I ukur_beban.py "C:/Users/mdpac/Downloads/Product Management R9.json" load $1 "/c/Users/mdpac/AppData/Local/Temp/claude/D--OJT-PM-Mock-Up/b7c0e9d4-00bf-4bac-b39f-e5c094f61065/scratchpad/hasil" > "/c/Users/mdpac/AppData/Local/Temp/claude/D--OJT-PM-Mock-Up/b7c0e9d4-00bf-4bac-b39f-e5c094f61065/scratchpad/hasil/log_$1.txt" 2>&1; echo "ukur $1 selesai $(date +%T)"; }
# (FH22 + ukur 1th sudah)
k=2
for y in 23 24 25 26; do
  $Q -c "select beban_prices(20$y)"
  for s in SS FH; do $Q -c "select beban_season('$s$y',$k)"; echo "$s$y $(date +%T)"; k=$((k+1)); done
  $Q -c "select beban_activity('FH$y')"
  if [ $y = 24 ]; then M 3th; fi
done
M 5th
