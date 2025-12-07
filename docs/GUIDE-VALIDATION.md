# Guide de Validation - TP27

## ✅ Checklist Complète

### Préparation

- [ ] Stack TP26 démarré (`docker compose up -d --build`)
- [ ] Tous les services UP (4 health checks OK)
- [ ] Livre "TP-Concurrency" créé avec stock=10
- [ ] ID du livre récupéré

### Test de Concurrence

- [ ] Script `loadtest.sh` exécutable (`chmod +x`)
- [ ] Test lancé: `./scripts/loadtest.sh BOOK_ID 50`
- [ ] Success ≈ 10
- [ ] Conflict ≈ 40  
- [ ] Other ≈ 0
- [ ] Stock final = 0 (vérifié via GET /api/books)
- [ ] Stock jamais négatif

### Test Résilience

- [ ] Pricing-service arrêté
- [ ] Livre "TP-Fallback" créé avec stock=10
- [ ] Test lancé: `./scripts/loadtest.sh ID 30`
- [ ] Success ≈ 10 avec price=0.0
- [ ] Conflict ≈ 20
- [ ] Pricing redémarré

### Observabilité

- [ ] `/actuator/metrics` exposé
- [ ] Métriques resilience4j visibles
- [ ] Au moins 3 métriques trouvées:
  - resilience4j.retry.calls
  - resilience4j.circuitbreaker.calls
  - resilience4j.circuitbreaker.state
- [ ] Logs resilience4j activés (optionnel)
- [ ] Transitions CB observées (optionnel)

### Livrables

- [ ] Captures d'écran des résultats
- [ ] Stock final vérifié
- [ ] Fallback démontré (price=0.0)
- [ ] Métriques capturées
- [ ] Rapport complété

---

## 🎯 Résultats Attendus par Scénario

### Scénario 1: Concurrence normale

**Config:** Stock=10, Requests=50

| Métrique | Valeur Attendue | Signification |
|----------|-----------------|---------------|
| Success (200) | ~10 | Stock initial |
| Conflict (409) | ~40 | Surplus de demandes |
| Other | ~0 | Pas d'erreurs |
| Stock final | 0 | Jamais < 0 |

### Scénario 2: Pricing down

**Config:** Stock=10, Requests=30, Pricing DOWN

| Métrique | Valeur Attendue | Signification |
|----------|-----------------|---------------|
| Success (200) | ~10 | Fallback actif |
| Price dans success | 0.0 | Valeur fallback |
| Conflict (409) | ~20 | Stock épuisé |
| Crash | Non | Résilience OK |

### Scénario 3: Stock épuisé

**Config:** Stock=0, Requests=10

| Métrique | Valeur Attendue | Signification |
|----------|-----------------|---------------|
| Success (200) | 0 | Pas de stock |
| Conflict (409) | 10 | Toutes refusées |

---

## 🔍 Dépannage Avancé

### Debug "Other" élevé

```bash
# 1. Vérifier les services
docker compose ps

# 2. Voir les logs
docker compose logs book-service-1
docker compose logs pricing-service

# 3. Tester manuellement
curl -v http://localhost:8081/api/books/1/borrow
```

### Vérifier le verrou DB

```bash
# Pendant le test, voir les locks MySQL
docker exec -it mysql-bookstore mysql -uroot -prootpass bookdb \
  -e "SHOW OPEN TABLES WHERE In_use > 0;"
```

### Observer les métriques en temps réel

```bash
# Boucle toutes les 2 secondes
while true; do 
  curl -s http://localhost:8081/actuator/metrics/resilience4j.retry.calls | jq
  sleep 2
done
```

---

## 📊 Interprétation des Métriques

### Retry Metrics

```json
{
  "name": "resilience4j.retry.calls",
  "measurements": [
    {"statistic": "COUNT", "value": 150},  // Total d'appels
    {"statistic": "VALUE", "value": 45}    // Avec retry
  ]
}
```

**Interprétation:**
- 150 appels totaux
- 45 ont nécessité un retry
- 105 ont réussi du premier coup

### Circuit Breaker State

```json
{
  "name": "resilience4j.circuitbreaker.state",
  "measurements": [
    {"statistic": "VALUE", "value": 0}  // 0=CLOSED, 1=OPEN, 2=HALF_OPEN
  ]
}
```

**États:**
- `0` = CLOSED (normal)
- `1` = OPEN (circuit coupé)
- `2` = HALF_OPEN (test)

---

## 💡 Conseils Pro

### 1. Logs structurés

```yaml
logging:
  level:
    io.github.resilience4j: DEBUG
  pattern:
    console: "%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n"
```

### 2. Monitoring en temps réel

```bash
# Terminal 1: Logs
docker compose logs -f book-service-1 | grep -i resilience

# Terminal 2: Métriques
watch -n 1 'curl -s http://localhost:8081/actuator/health | jq'

# Terminal 3: Load test
./scripts/loadtest.sh 1 100
```

### 3. Générer un rapport automatique

```bash
# Créer un script de collecte
cat > collect-metrics.sh << 'EOF'
#!/bin/bash
echo "=== Health Checks ==="
curl -s http://localhost:8081/actuator/health | jq

echo -e "\n=== Retry Metrics ==="
curl -s http://localhost:8081/actuator/metrics/resilience4j.retry.calls | jq

echo -e "\n=== Circuit Breaker ==="
curl -s http://localhost:8081/actuator/metrics/resilience4j.circuitbreaker.calls | jq

echo -e "\n=== Stock État ==="
curl -s http://localhost:8081/api/books | jq
EOF

chmod +x collect-metrics.sh
./collect-metrics.sh > rapport-metriques.txt
```

---

**Bonne validation!** 🚀
