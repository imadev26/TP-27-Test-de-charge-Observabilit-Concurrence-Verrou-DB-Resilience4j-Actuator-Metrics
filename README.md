# TP 27 : Test de Charge & Observabilité

## 🎯 Ce que ce TP permet de vérifier

- ✅ **Concurrence** : 50+ emprunts simultanés sur 3 instances
- ✅ **Verrou DB** : Stock ne devient jamais négatif
- ✅ **Résilience** : Fallback quand pricing-service tombe
- ✅ **Observabilité** : Métriques Actuator (Retry + Circuit Breaker)

> [!NOTE]
> Ce TP est la **suite pratique du TP26**. Il faut d'abord avoir le stack TP26 fonctionnel.

---

## 📋 Prérequis

### Stack TP26 démarré

```bash
# Depuis le dossier TP26
docker compose up -d --build
```

### Vérifier que tout est UP

```bash
curl -s http://localhost:8082/actuator/health  # pricing-service
curl -s http://localhost:8081/actuator/health  # book-service-1
curl -s http://localhost:8083/actuator/health  # book-service-2
curl -s http://localhost:8084/actuator/health  # book-service-3
```

**✅ Checkpoint:** Chaque commande doit renvoyer `"status":"UP"`

> [!WARNING]
> Si un service n'est pas UP, ne pas lancer le test : vous allez juste produire des erreurs "Other"

---

## 📚 Partie A — Préparer le terrain

### Étape A1 — Créer un livre avec stock connu

```bash
curl -X POST http://localhost:8081/api/books \
  -H "Content-Type: application/json" \
  -d '{"title":"TP-Concurrency","author":"Demo","stock":10}'
```

**Résultat attendu:** HTTP 201 + JSON du livre avec `id`

### Étape A2 — Récupérer l'ID du livre

```bash
curl -s http://localhost:8081/api/books
```

Repérer l'`id` du livre "TP-Concurrency"

**Dans la suite:** Remplacer `BOOK_ID` par cet ID

---

## ✅ Partie B — Sanity Check : 1 emprunt simple

### Étape B1 — Tester borrow (sans concurrence)

```bash
curl -X POST http://localhost:8081/api/books/BOOK_ID/borrow
```

**Attendu:**
- Réponse 200
- JSON avec:
  - `stockLeft` décrémenté
  - `price > 0` (si pricing-service UP)

> [!TIP]
> Cette étape confirme que l'API fonctionne, le livre existe, et pricing répond

---

## 🔥 Partie C — Test de Charge : 50 emprunts en parallèle

### Étape C1 — Script loadtest.sh (Linux/Mac)

**Fichier:** `scripts/loadtest.sh`

```bash
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
```

**Rendre exécutable:**
```bash
chmod +x scripts/loadtest.sh
```

### Étape C2 — Lancer le test

```bash
./scripts/loadtest.sh BOOK_ID 50
```

### Résultats attendus

**Si stock initial = 10 et requests = 50:**
- ✅ Success (200): **≈ 10**
- ✅ Conflict (409): **≈ 40**
- ✅ Other: **≈ 0**

**Signification:**
- `200` = emprunt réussi
- `409` = plus d'exemplaires (comportement correct)
- `Other` = problème (service down, mauvais ID, etc.)

---

## 💻 Partie D — Test de Charge Windows (PowerShell)

### Étape D1 — Script loadtest.ps1

**Fichier:** `scripts/loadtest.ps1`

```powershell
param(
  [int]$BookId = 1,
  [int]$Requests = 50
)

$Ports = @(8081, 8083, 8084)

Write-Host "== Load test =="
Write-Host "BookId=$BookId Requests=$Requests"
Write-Host "Ports=$($Ports -join ',')"
Write-Host ""

$jobs = @()

for ($i=1; $i -le $Requests; $i++) {
  $port = $Ports[$i % 3]
  $url = "http://localhost:$port/api/books/$BookId/borrow"

  $jobs += Start-Job -ScriptBlock {
    param($u, $p)
    try {
      $resp = Invoke-WebRequest -Uri $u -Method POST -UseBasicParsing
      [PSCustomObject]@{ Port=$p; Status=$resp.StatusCode; Body=$resp.Content }
    } catch {
      if ($_.Exception.Response -ne $null) {
        $status = $_.Exception.Response.StatusCode.value__
        $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
        [PSCustomObject]@{ Port=$p; Status=$status; Body=$body }
      } else {
        [PSCustomObject]@{ Port=$p; Status=-1; Body=$_.Exception.Message }
      }
    }
  } -ArgumentList $url, $port
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$success  = ($results | Where-Object {$_.Status -eq 200}).Count
$conflict = ($results | Where-Object {$_.Status -eq 409}).Count
$other    = $Requests - $success - $conflict

Write-Host "== Résultats =="
Write-Host "Success (200):  $success"
Write-Host "Conflict (409): $conflict"
Write-Host "Other:          $other"
```

### Étape D2 — Exécuter

```powershell
.\scripts\loadtest.ps1 -BookId BOOK_ID -Requests 50
```

---

## 🔒 Partie E — Vérifier "Stock jamais négatif"

### Étape E1 — Lire l'état du stock final

```bash
curl -s http://localhost:8081/api/books
```

**Attendu:**
- ✅ Le livre "TP-Concurrency" a `stock = 0`
- ✅ **Jamais** `stock < 0`

### Pourquoi ça marche ?

**Verrou DB:** `findByIdForUpdate()` met un verrou MySQL sur la ligne du livre pendant `@Transactional`

> [!IMPORTANT]
> **Sans verrou DB**, sous charge, vous risquez:
> - Stock incohérent
> - Stock négatif
> - Race conditions

---

## 🛡️ Partie F — Résilience : pricing down → fallback

### Étape F1 — Arrêter pricing-service

```bash
docker compose stop pricing-service
```

**Checkpoint:**
```bash
curl -s http://localhost:8082/actuator/health  # Échoue (normal)
```

### Étape F2 — Créer un nouveau livre

```bash
curl -X POST http://localhost:8081/api/books \
  -H "Content-Type: application/json" \
  -d '{"title":"TP-Fallback","author":"Demo","stock":10}'
```

**Récupérer l'ID:**
```bash
curl -s http://localhost:8081/api/books
```

### Étape F3 — Relancer le test (30 requêtes)

```bash
./scripts/loadtest.sh ID_FALLBACK 30
```

**Attendu:**
- ✅ Succès: **≈ 10**
- ✅ Conflits: **≈ 20**
- ✅ Dans les succès, **price = 0.0** (fallback)

> [!TIP]
> Ouvrir `success.txt` (dossier affiché) pour vérifier les JSON

### Étape F4 — Redémarrer pricing

```bash
docker compose start pricing-service
```

---

## 📊 Partie G — Observabilité : Actuator Metrics

### Étape G1 — Exposer /actuator/metrics

**Dans:** `book-service/src/main/resources/application.yml`

```yaml
management:
  endpoints:
    web:
      exposure:
        include: "health,info,metrics"
```

**Rebuild + restart:**
```bash
docker compose up -d --build
```

**Checkpoint:**
```bash
curl -s http://localhost:8081/actuator/metrics
```

**Attendu:** Liste de métriques

### Étape G2 — Trouver les métriques Resilience4j

**Linux/Mac:**
```bash
curl -s http://localhost:8081/actuator/metrics | grep -i resilience
```

**Windows PowerShell:**
```powershell
(Invoke-RestMethod http://localhost:8081/actuator/metrics).names | Select-String -Pattern "resilience"
```

### Métriques à observer

Pendant que pricing est down et loadtest tourne:

- ✅ **Retry** : Augmentation des tentatives
- ✅ **Circuit Breaker** : État OPEN après seuil
- ✅ **Fallback** : Appels au fallback

### Activer les logs (optionnel)

**Dans application.yml:**
```yaml
logging:
  level:
    io.github.resilience4j: INFO
```

**Voir les logs:**
```bash
docker compose logs -f book-service-1
```

**Transitions observables:** `CLOSED → OPEN → HALF_OPEN`

---

## 📝 Travail Demandé

### 1. Captures / Preuves

- [ ] Résultat `loadtest.sh BOOK_ID 50` (succès/conflits)
- [ ] `curl /api/books` montrant stock final = 0
- [ ] Test fallback : pricing stop + loadtest + preuve price=0.0
- [ ] `/actuator/metrics` montrant métriques resilience

### 2. Conclusion (5 lignes minimum)

**Questions à répondre:**

1. **Pourquoi le verrou DB est nécessaire en multi-instances ?**
   
2. **Quel est le rôle du circuit breaker ?**

3. **Quel est le rôle du fallback ?**

---

## 🎯 Scénarios de Validation

| Test | Stock Initial | Requests | Success Attendu | Conflict Attendu |
|------|---------------|----------|-----------------|------------------|
| Concurrence normale | 10 | 50 | 10 | 40 |
| Pricing down | 10 | 30 | 10 (price=0.0) | 20 |
| Stock épuisé | 0 | 10 | 0 | 10 |

---

## 🔍 Dépannage

### "Other" errors élevé

**Causes possibles:**
- Service pas UP (vérifier health)
- Mauvais BOOK_ID
- Timeout réseau

### Stock négatif observé

**Problème:** Verrou DB pas actif
**Solution:** Vérifier `@Lock(PESSIMISTIC_WRITE)` dans repository

### Fallback ne marche pas

**Causes:**
- Signature fallback incorrecte
- Circuit breaker pas configuré
- Retry non configuré

---

## 📈 Métriques Resilience4j

### Retry Metrics

```bash
curl http://localhost:8081/actuator/metrics/resilience4j.retry.calls
```

### Circuit Breaker Metrics

```bash
curl http://localhost:8081/actuator/metrics/resilience4j.circuitbreaker.state
curl http://localhost:8081/actuator/metrics/resilience4j.circuitbreaker.calls
```

### Interprétation

| Métrique | Signification |
|----------|---------------|
| `successful_without_retry` | Appels OK du premier coup |
| `successful_with_retry` | Appels OK après retry |
| `failed_without_retry` | Échecs sans retry |
| `failed_with_retry` | Échecs après retry |

---

## 👨‍💻 Auteur

**Imad ADAOUMOUM**

## 📄 License

Ce projet est réalisé dans un cadre académique.
