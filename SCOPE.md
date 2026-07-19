# tf-mod-aws-batch — SCOPE

Composite module for AWS Batch: a compute environment, a job queue, a job definition,
and an optional fair-share scheduling policy. It provisions managed batch compute
(Fargate or EC2/Spot) with encrypted storage and private networking, aligned with the
Casey's (NPI / GLBA / FCA) baseline.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_batch_compute_environment.this`

## In-scope resources

The module manages **all** of the following (allow-list):

- `aws_batch_compute_environment` — keystone (MANAGED, Fargate/EC2/Spot)
- `aws_batch_job_queue` — queue bound to the compute environment(s)
- `aws_batch_job_definition` — container/Fargate job definition
- `aws_batch_scheduling_policy` — optional fair-share scheduling policy

## Out-of-scope resources (consumed by reference)

Referenced by `arn`/`id`, never created here:

- VPC subnets — `subnet_ids` (from `tf-mod-aws-vpc`)
- Security groups — `security_group_ids` (from `tf-mod-aws-security-group`)
- Batch service role / EC2 instance role + instance profile / job execution & job role / Spot fleet role — `arn` (from `tf-mod-aws-iam-role`)
- KMS CMK for EBS / log encryption — `kms_key_arn` (from `tf-mod-aws-kms`)
- ECR image — image URI (from `tf-mod-aws-ecr`)
- CloudWatch log group for job logs — `log_group_name` (from `tf-mod-aws-cloudwatch-log-group`)
- EC2 launch template (optional) — id (from `tf-mod-aws-launch-template`)

## Consumes

| Input | Type | Source module |
|---|---|---|
| `subnet_ids` | `list(string)` | `tf-mod-aws-vpc` |
| `security_group_ids` | `list(string)` | `tf-mod-aws-security-group` |
| `service_role_arn` | `string` (IAM role ARN, optional with SLR) | `tf-mod-aws-iam-role` |
| `instance_role_arn` | `string` (instance profile ARN, EC2 only) | `tf-mod-aws-iam-role` |
| `spot_iam_fleet_role_arn` | `string` (Spot fleet role ARN, Spot only) | `tf-mod-aws-iam-role` |
| `job_definition.execution_role_arn` / `job_role_arn` | `string` (IAM role ARN) | `tf-mod-aws-iam-role` |
| `kms_key_arn` | `string` (KMS key ARN) | `tf-mod-aws-kms` |

## Required IAM permissions

Least-privilege actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `batch:CreateComputeEnvironment`, `batch:UpdateComputeEnvironment`, `batch:DeleteComputeEnvironment`, `batch:DescribeComputeEnvironments` | Compute environment |
| `batch:CreateJobQueue`, `batch:UpdateJobQueue`, `batch:DeleteJobQueue`, `batch:DescribeJobQueues` | Job queue |
| `batch:RegisterJobDefinition`, `batch:DeregisterJobDefinition`, `batch:DescribeJobDefinitions` | Job definition |
| `batch:CreateSchedulingPolicy`, `batch:UpdateSchedulingPolicy`, `batch:DeleteSchedulingPolicy`, `batch:DescribeSchedulingPolicy` | Fair-share scheduling |
| `iam:PassRole` | **Pass the Batch service role, EC2 instance profile, Spot fleet role, and job execution/job roles** (scope to those ARNs) |
| `iam:CreateServiceLinkedRole` | `AWSServiceRoleForBatch` (and EC2 Spot when applicable) |
| `batch:TagResource`, `batch:UntagResource`, `batch:ListTagsForResource` | Tagging |
| `ec2:Describe*` | Managed-compute validation (subnet / SG / launch-template lookups during plan/apply) |

`iam:PassRole` is **mandatory** for every role Batch consumes — scope it to the exact role
ARNs and add an `iam:PassedToService` condition (`batch.amazonaws.com`,
`ecs-tasks.amazonaws.com`, `ec2.amazonaws.com`, `spotfleet.amazonaws.com`). If storage/logs
use a CMK, also `kms:DescribeKey` on the key ARN.

## AWS Prerequisites

- **Service-linked role:** AWS Batch auto-creates `AWSServiceRoleForBatch` (needs
  `iam:CreateServiceLinkedRole`); in v6 the provider prefers the SLR over an explicit
  service role for MANAGED compute environments.
- **`iam:PassRole`** for: the Batch service role (if explicit), the EC2 instance profile
  (EC2 compute), the Spot fleet role `AmazonEC2SpotFleetTaggingRole` (EC2 Spot —
  docs.aws.amazon.com/batch/latest/userguide/spot-fleet-roles-cli.html), and the job
  definition's execution role + job role.
- **Networking:** subnets and security groups in the target VPC; Fargate requires
  `awsvpc` networking and typically private subnets with a NAT/VPC endpoints for image pulls.
- **ECR/image:** container images reachable from the compute environment.
- **CMK (optional but default-on posture):** EC2/Spot EBS volumes are encrypted with a CMK
  set on the **launch template** (`tf-mod-aws-launch-template`); Fargate ephemeral storage is
  AWS-managed-encrypted automatically; log encryption is via the CMK on the CloudWatch log group.
- **Region:** AWS Batch is regional with no us-east-1 global-service coupling; the module
  declares no `region` variable and inherits the caller's provider.
- **Quotas** (fixed, per-Region — docs.aws.amazon.com/batch/latest/userguide/service_limits.html):
  **50** compute environments across ECS+EKS, **50** job queues, **5** CEs per EKS cluster,
  **3** CEs bindable per queue, job-definition size **≤ 24 KiB**, array-job size **≤ 10,000**.
  EC2/Spot **vCPU service quotas** (separate, adjustable) bound `compute_resources.max_vcpus`.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Compute environment id (ARN form) | most consumers |
| `arn` | Compute environment ARN (`arn:aws:batch:<region>:<account>:compute-environment/<name>`) — cross-resource reference type | IAM policies, monitoring |
| `name` | Compute environment name | job queue binding |
| `job_queue_arn` | Job queue ARN | job submission |
| `job_definition_arn` | Job definition ARN (`...:job-definition/<name>:<rev>`) | job submission, EventBridge targets |
| `scheduling_policy_arn` | Fair-share scheduling policy ARN | job queue binding |
| `tags_all` | All tags incl. provider `default_tags` | governance/audit |

## Provider gotchas

- **`compute_environment_name` is FORCE-NEW**; many `compute_resources` fields
  (`type`, `subnets`, allocation strategy) force replacement.
- **Update ordering.** A queue references compute environments by ARN — a compute
  environment in use by a queue cannot be deleted until detached/disabled; disable the
  queue, then the CE, on destroy.
- **Job definition revisions.** `aws_batch_job_definition` registers a **new revision** on
  change (effectively immutable per revision).
- **Compute environment state.** Updating certain settings requires the CE to be `DISABLED`;
  the provider may briefly disable/enable it.
- **`tags` vs `tags_all`.** `var.tags` flows to each Batch resource; `tags_all` merges
  resource tags over provider `default_tags` (resource tags win); `default_tags` is the
  caller's concern.
- **`arn` is the cross-resource reference type.**

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Networking | private subnets, no auto-assigned public IP | public subnet (discouraged) |
| Storage encryption | EBS / managed storage encrypted (CMK via `kms_key_arn`, else AWS-managed) | n/a |
| Job logging | `awslogs` to CloudWatch | alternate driver |
| Capacity type | Fargate by default (no host management); EC2/Spot opt-in | set `compute_resources.type = EC2`/`SPOT` |
| Least-privilege | distinct execution role and job role on the job definition | n/a |

## Design decisions

- One composite owns the compute environment, queue, job definition, and (optional)
  scheduling policy so a runnable batch pipeline comes from a single call; roles,
  networking, and CMK are referenced by ARN from sibling modules.
- The fair-share scheduling policy and EC2/Spot compute are **optional** (`optional(object(...))`
  / `map(object(...))`, default empty/Fargate) and rendered via `dynamic` blocks.
- Container properties are supplied as a typed object (with rendered command/env where
  needed), keeping the job definition explicit without an `any` escape hatch.
