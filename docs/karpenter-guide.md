# Karpenter guide

Full resource definitions: `modules/eks-addons/karpenter.tf`.

## NodePools

| NodePool | Capacity type | Consolidation | Disruption budget |
| --- | --- | --- | --- |
| `general-purpose` | On-demand | `WhenEmptyOrUnderutilized`, 1 minute | none (on-demand isn't cost-sensitive the same way) |
| `general-purpose-spot` | Spot, diversified `m6i`/`m6a`/`m5`/`m5a` | `WhenEmptyOrUnderutilized`, 30 seconds | max 50% of spot nodes disrupted at once |

Both reference one shared `EC2NodeClass` (`default`) — AL2023 AMI family, the same node IAM role
(`modules/eks`'s `node_role_name`) every managed node group uses, subnets discovered by the
`kubernetes.io/role/internal-elb` tag `modules/vpc` already applies (Phase 2), security group
discovered by ID (the same `eks-node-sg` every other node uses).

## Spot interruption handling

An SQS queue + three EventBridge rules (spot interruption warning, rebalance recommendation,
instance state change) feed Karpenter's own interruption controller — a node gets a 2-minute
warning before spot reclamation and Karpenter cordons/drains it proactively, rather than the pod
disappearing without notice.

## Why Karpenter itself never runs on a Karpenter-provisioned node

`nodeSelector`/`toleration` pin the Karpenter controller pods to the `system` managed node group
(tainted, on-demand, never spot) — Karpenter managing its own risk of being evicted by the exact
mechanism it operates is a real, avoidable failure mode.

## Capacity reservations

Not configured in this phase — no `capacityReservationSelectorTerms` on the `EC2NodeClass`. Revisit
if a specific instance type/AZ combination becomes hard to obtain via standard on-demand/spot at
the "scale" growth tier (`cloud-architecture-blueprint.md` Section 13).
