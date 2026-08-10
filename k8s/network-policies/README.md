# NetworkPolicies (Bonus 5.4)

Restricts pod-to-pod traffic inside `retail-app` so each service can only be
reached by the services that actually call it:

- `ui` → reachable from the internet (via the ALB) and calls `catalog`,
  `carts`, `orders`, `checkout`.
- `checkout` → reachable from `ui`; calls `catalog`, `carts`, `orders`,
  `rabbitmq`.
- `catalog` → reachable from `ui`, `checkout`. Cannot be reached by `orders`
  or `carts`.
- `carts` → reachable from `ui`, `checkout`. Uses `redis` (in-cluster).
- `orders` → reachable from `ui`, `checkout`. **Not** reachable from
  `catalog`. Uses `rabbitmq` (in-cluster).
- `rabbitmq` → reachable from `orders`, `checkout`.
- `redis` → reachable from `carts`.

A namespace-wide `deny-all-ingress` policy sets the default, and each
`allow-*-ingress.yaml` file punches the one hole each service needs. Only
`Ingress` is restricted — `Egress` is left open so pods can still reach
RDS, DynamoDB, Secrets Manager, and DNS without a separate allow-list.

## Apply

```bash
kubectl apply -f k8s/network-policies/
```

## Before you apply — check the label selectors

These policies select pods via `app.kubernetes.io/name`, which is the
label convention the upstream retail-store-sample-app Helm chart uses as
of the version pinned in `terraform/modules/app/main.tf`. **Confirm this
still matches before applying**, since label conventions can drift between
chart versions:

```bash
kubectl get pods -n retail-app --show-labels
```

If the labels differ, update the `podSelector.matchLabels` values in each
file accordingly.

## Verify

```bash
# Should succeed (ui -> catalog is allowed)
kubectl exec -n retail-app deploy/ui -- curl -s -o /dev/null -w "%{http_code}\n" http://catalog/health

# Should hang/fail (catalog -> orders is NOT allowed)
kubectl exec -n retail-app deploy/catalog -- curl -s --max-time 5 -o /dev/null -w "%{http_code}\n" http://orders/health
```
