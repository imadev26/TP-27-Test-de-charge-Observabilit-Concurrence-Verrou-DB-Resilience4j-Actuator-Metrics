#!/usr/bin/env bash
set -euo pipefail

BOOK_ID="${1:-1}"
REQUESTS="${2:-50}"

# Répartir sur 3 instances
PORTS=(8081 8083 8084)

echo "== Load test =="
echo "BookId=$BOOK_ID Requests=$REQUESTS"
echo "Ports=${PORTS[*]}"
echo

tmpdir="$(mktemp -d)"
success_file="$tmpdir/success.txt"
conflict_file="$tmpdir/conflict.txt"
other_file="$tmpdir/other.txt"

touch "$success_file" "$conflict_file" "$other_file"

run_one() {
  local i="$1"
  local port="${PORTS[$((i % 3))]}"
  local url="http://localhost:${port}/api/books/${BOOK_ID}/borrow"

  # -s: silent, -o: body in file, -w: status code
  local body_file="$tmpdir/body_$i.json"
  local status
  status="$(curl -s -o "$body_file" -w "%{http_code}" -X POST "$url" || true)"

  if [[ "$status" == "200" ]]; then
    echo "$port $status $(cat "$body_file")" >> "$success_file"
  elif [[ "$status" == "409" ]]; then
    echo "$port $status $(cat "$body_file")" >> "$conflict_file"
  else
    echo "$port $status $(cat "$body_file" 2>/dev/null || echo '')" >> "$other_file"
  fi
}

pids=()
for i in $(seq 1 "$REQUESTS"); do
  run_one "$i" &
  pids+=($!)
done

for p in "${pids[@]}"; do
  wait "$p"
done

echo "== Résultats =="
echo "Success (200):  $(wc -l < "$success_file")"
echo "Conflict (409): $(wc -l < "$conflict_file")"
echo "Other:          $(wc -l < "$other_file")"
echo
echo "Fichiers détails: $tmpdir"
echo " - success.txt  : appels OK"
echo " - conflict.txt : stock épuisé (normal)"
echo " - other.txt    : erreurs à diagnostiquer"
