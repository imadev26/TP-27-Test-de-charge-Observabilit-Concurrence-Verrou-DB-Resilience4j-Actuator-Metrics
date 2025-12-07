# Rapport TP 27 - Test de Charge & Observabilité

**Étudiant:** [Votre nom]  
**Date:** [Date]

---

## 1. Test de Concurrence (50 requêtes parallèles)

### Configuration
- **Livre:** TP-Concurrency
- **Stock initial:** 10
- **Nombre de requêtes:** 50
- **Instances testées:** 3 (ports 8081, 8083, 8084)

### Résultats

```
== Résultats ==
Success (200):  [À remplir]
Conflict (409): [À remplir]
Other:          [À remplir]
```

### Capture d'écran

[Insérer capture du résultat loadtest.sh]

---

## 2. Vérification Stock Final

### Commande

```bash
curl -s http://localhost:8081/api/books
```

### Résultat

```json
[Coller ici le JSON du livre TP-Concurrency]
```

### ✅ Vérification

- [ ] Stock final = 0
- [ ] Stock jamais négatif
- [ ] Titre = "TP-Concurrency"

---

## 3. Test Résilience (Pricing Down)

### Configuration
- **Livre:** TP-Fallback
- **Stock initial:** 10
- **Requêtes:** 30
- **Pricing-service:** ARRÊTÉ

### Résultats

```
== Résultats ==
Success (200):  [À remplir]
Conflict (409): [À remplir]
Other:          [À remplir]
```

### Exemple de réponse avec fallback

```json
[Coller un exemple de JSON avec price=0.0]
```

### ✅ Vérification

- [ ] Succès ≈ 10
- [ ] Price = 0.0 dans tous les succès
- [ ] Pas de crash malgré pricing down

---

## 4. Métriques Actuator

### Liste des métriques Resilience4j

```bash
curl -s http://localhost:8081/actuator/metrics | grep resilience
```

**Résultat:**
```
[Coller la liste des métriques ici]
```

### Détail d'une métrique (retry)

```bash
curl http://localhost:8081/actuator/metrics/resilience4j.retry.calls
```

**Résultat:**
```json
[Coller le JSON ici]
```

### ✅ Métriques observées

- [ ] `resilience4j.retry.calls`
- [ ] `resilience4j.circuitbreaker.calls`
- [ ] `resilience4j.circuitbreaker.state`

---

## 5. Conclusion (minimum 5 lignes)

### Pourquoi le verrou DB est nécessaire en multi-instances ?

[Votre réponse ici]

**Points clés à aborder:**
- 3 instances = 3 JVM différentes
- synchronized ne protège que dans une JVM
- Sans verrou DB = race conditions
- PESSIMISTIC_WRITE garantit l'atomicité

### Quel est le rôle du circuit breaker ?

[Votre réponse ici]

**Points clés à aborder:**
- Surveille le taux d'échec
- Coupe les appels si trop d'échecs
- Évite de surcharger un service déjà en panne
- Transitions: CLOSED → OPEN → HALF_OPEN

### Quel est le rôle du fallback ?

[Votre réponse ici]

**Points clés à aborder:**
- Valeur par défaut quand erreur
- Évite que tout le système plante
- Dégrade gracieusement (price=0.0)
- Permet de continuer le service

---

## 6. Observations Supplémentaires

[Vos observations, difficultés rencontrées, points intéressants]

---

## 7. Annexes

### Logs Circuit Breaker

```
[Si vous avez activé les logs, coller un exemple ici]
```

### Commandes utilisées

```bash
# Créer le livre
curl -X POST http://localhost:8081/api/books \
  -H "Content-Type: application/json" \
  -d '{"title":"TP-Concurrency","author":"Demo","stock":10}'

# Lancer le test
./scripts/loadtest.sh 1 50

# Arrêter pricing
docker compose stop pricing-service

# Voir les métriques
curl http://localhost:8081/actuator/metrics
```

---

**Signature:**  
[Votre nom]  
[Date]
