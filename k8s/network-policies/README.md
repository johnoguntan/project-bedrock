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

## Known limitation — enforcement unverified

As of this deployment, all 8 policies apply cleanly to the cluster and their
`podSelector`s were corrected to match the actual chart labels (`orders-rabbitmq-0`
and `checkout-redis-...` carry `app.kubernetes.io/name=orders`/`checkout` rather
than `rabbitmq`/`redis` — see the two `app.kubernetes.io/component` selectors in
`06-allow-brokers-ingress.yaml`).

Runtime *enforcement* could not be confirmed end-to-end. The VPC CNI's network
policy agent (`aws-eks-nodeagent`, `aws-network-policy-agent:v1.3.5`) is present
and running, `ENABLE_NETWORK_POLICY=true` and `NETWORK_POLICY_ENFORCING_MODE=standard`
are set on `aws-node`, and RBAC for the `aws-node` service account was extended
with a supplementary ClusterRole/Binding (`aws-node-policy-endpoints`) to permit
writes to the `policyendpoints.networking.k8s.aws` CRD — but no `PolicyEndpoint`
objects were ever created for `retail-app`, and the `aws-node` container's own
logs couldn't be inspected (fully distroless image, no shell/`cat`/`grep`/`tar`
in the container to exec into). A verification curl from `catalog` to `orders`
still succeeded (`404`, not a timeout), confirming enforcement is not active.

Root cause is unresolved. Suspected causes, in order of likelihood: (1) this
cluster's VPC CNI was installed outside the EKS-managed add-on system (bundled
with cluster creation rather than via `aws_eks_addon`), so it may be missing a
config surface only present in the managed add-on's install manifest; (2) a
version-specific requirement not captured in `ENABLE_NETWORK_POLICY`/
`NETWORK_POLICY_ENFORCING_MODE` alone for this CNI build. Next step to actually
resolve: convert `vpc-cni` to an EKS-managed add-on (`aws eks create-addon`) so
it installs the current reference manifest, or attach a debug container to a
node via `kubectl debug node/<node> -it --image=busybox` and read
`/var/log/aws-routed-eni/ipamd.log` directly from the hostPath.
