###############################################################################
# Identity — compute environment (keystone)
###############################################################################

variable "name" {
 description = <<EOT
Name of the AWS Batch compute environment (the keystone resource). FORCE-NEW —
changing this destroys and recreates the compute environment (and forces the job
queue that binds to it to re-point). Up to 128 letters, numbers, and
underscores. Mutually exclusive with name_prefix; leave both null to let the
provider assign a random unique name.
EOT
 type = string
 default = null

 validation {
 condition = !(var.name != null && var.name_prefix != null)
 error_message = "Set at most one of name or name_prefix; they are mutually exclusive."
 }
}

variable "name_prefix" {
 description = <<EOT
Creates a unique compute-environment name beginning with this prefix. FORCE-NEW.
Conflicts with name. Prefer name_prefix for generated/ephemeral environments so
plans never collide on a hard-coded name.
EOT
 type = string
 default = null
}

###############################################################################
# Compute environment — required / core configuration
###############################################################################

variable "compute_environment_type" {
 description = <<EOT
Type of the compute environment: MANAGED (AWS Batch provisions and scales the
compute, the default and recommended posture) or UNMANAGED (you manage the
underlying ECS compute yourself). compute_resources is required for MANAGED and
must be omitted for UNMANAGED.
EOT
 type = string
 default = "MANAGED"

 validation {
 condition = contains(["MANAGED", "UNMANAGED"], var.compute_environment_type)
 error_message = "compute_environment_type must be either \"MANAGED\" or \"UNMANAGED\"."
 }
}

variable "state" {
 description = <<EOT
State of the compute environment. ENABLED (default) lets the environment accept
jobs from a queue and scale out automatically; DISABLED quiesces it. A compute
environment must be DISABLED (and detached from any queue) before it can be
deleted — see the destroy-ordering note in the module README.
EOT
 type = string
 default = "ENABLED"

 validation {
 condition = contains(["ENABLED", "DISABLED"], var.state)
 error_message = "state must be either \"ENABLED\" or \"DISABLED\"."
 }
}

variable "subnet_ids" {
 description = <<EOT
VPC subnets into which managed compute resources are launched. Wire from
tf_mod_aws_vpc. SECURE DEFAULT: use private subnets — Fargate and EC2 batch
compute need outbound reachability to ECR/STS/CloudWatch via a NAT gateway or
interface VPC endpoints, never an inbound public path. Required for MANAGED
compute environments; ignored for UNMANAGED.
EOT
 type = list(string)
 default = []

 validation {
 condition = var.compute_environment_type != "MANAGED" || length(var.subnet_ids) > 0
 error_message = "subnet_ids must contain at least one subnet for a MANAGED compute environment."
 }
}

variable "security_group_ids" {
 description = <<EOT
Security groups associated with the compute resources. Wire from
tf_mod_aws_security_group. Required for Fargate compute environments. SECURE
DEFAULT: attach least-privilege egress-only groups; Batch workloads are
typically egress-only (image pulls, API calls) and need no ingress.
EOT
 type = list(string)
 default = []

 validation {
 condition = var.compute_environment_type != "MANAGED" || !startswith(var.compute_resources.type, "FARGATE") || length(var.security_group_ids) > 0
 error_message = "security_group_ids must contain at least one group for a Fargate (FARGATE/FARGATE_SPOT) compute environment."
 }
}

###############################################################################
# Compute environment — IAM roles (consumed by ARN from tf_mod_aws_iam_role)
###############################################################################

variable "service_role_arn" {
 description = <<EOT
Full ARN of the IAM role that lets AWS Batch call other AWS services on your
behalf. Wire from tf_mod_aws_iam_role. Leave null (default) to let AWS Batch use
the AWSServiceRoleForBatch service-linked role, which the v6 provider prefers for
MANAGED compute environments — this is the recommended posture. The Terraform
identity needs iam:PassRole on this ARN when set.
EOT
 type = string
 default = null

 validation {
 condition = var.service_role_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::", coalesce(var.service_role_arn, "x")))
 error_message = "service_role_arn must be an IAM role ARN (arn:aws:iam::...) or null."
 }
}

variable "instance_role_arn" {
 description = <<EOT
ARN of the ECS instance profile applied to EC2 instances in the compute
environment (EC2/SPOT only). Wire from tf_mod_aws_iam_role (instance_profile_arn).
Not applicable to Fargate — leave null. The Terraform identity needs
iam:PassRole on this ARN when set.
EOT
 type = string
 default = null
}

variable "spot_iam_fleet_role_arn" {
 description = <<EOT
ARN of the Amazon EC2 Spot Fleet IAM role (AmazonEC2SpotFleetTaggingRole) for a
SPOT compute environment. Wire from tf_mod_aws_iam_role. Required when
compute_resources.type = SPOT; not applicable to Fargate or On-Demand EC2 —
leave null. The Terraform identity needs iam:PassRole on this ARN when set.
EOT
 type = string
 default = null
}

###############################################################################
# Compute environment — managed compute resources
###############################################################################

variable "compute_resources" {
 description = <<EOT
Managed compute resources for the environment. SECURE DEFAULT: Fargate (no host
management, AWS-managed ephemeral-storage encryption). subnets and
security_group_ids are supplied from the top-level subnet_ids /
security_group_ids variables; instance_role / spot_iam_fleet_role come from the
top-level instance_role_arn / spot_iam_fleet_role_arn variables.

 - type: FARGATE (default) | FARGATE_SPOT | EC2 | SPOT.
 - max_vcpus: maximum vCPUs the environment can reach (default 16).
 - min_vcpus: minimum vCPUs to maintain (EC2/SPOT only).
 - desired_vcpus: desired vCPUs (EC2/SPOT only; Batch manages it after).
 - allocation_strategy: EC2/SPOT allocation strategy (see validation).
 - bid_percentage: max Spot price as % of On-Demand (SPOT only).
 - instance_types: EC2 instance types/families to launch (EC2/SPOT only).
 - ec2_key_pair: EC2 key pair for SSH (EC2/SPOT only; discouraged).
 - image_id: AMI override (EC2/SPOT only; prefer ec2_configuration).
 - placement_group: EC2 placement group (EC2/SPOT only).
 - ec2_configuration: AMI selection overrides (EC2/SPOT only).
 - launch_template: reference an external launch template — the place to
 set CMK-encrypted EBS via tf_mod_aws_launch_template.
 - tags: extra tags applied to launched EC2 resources, merged
 over module tags (EC2/SPOT only).

Fargate ignores the EC2-only fields; leave them null for Fargate environments.
EOT
 type = object({
 type = optional(string, "FARGATE")
 max_vcpus = optional(number, 16)
 min_vcpus = optional(number)
 desired_vcpus = optional(number)
 allocation_strategy = optional(string)
 bid_percentage = optional(number)
 instance_types = optional(set(string))
 ec2_key_pair = optional(string)
 image_id = optional(string)
 placement_group = optional(string)
 ec2_configuration = optional(list(object({
 image_id_override = optional(string)
 image_kubernetes_version = optional(string)
 image_type = optional(string)
 })), [])
 launch_template = optional(object({
 launch_template_id = optional(string)
 launch_template_name = optional(string)
 version = optional(string)
 }))
 tags = optional(map(string), {})
 })
 default = {}

 validation {
 condition = contains(["FARGATE", "FARGATE_SPOT", "EC2", "SPOT"], var.compute_resources.type)
 error_message = "compute_resources.type must be one of FARGATE, FARGATE_SPOT, EC2, or SPOT."
 }

 validation {
 condition = var.compute_resources.allocation_strategy == null || contains(["BEST_FIT", "BEST_FIT_PROGRESSIVE", "SPOT_CAPACITY_OPTIMIZED", "SPOT_PRICE_CAPACITY_OPTIMIZED"],
 coalesce(var.compute_resources.allocation_strategy, "x"))
 error_message = "compute_resources.allocation_strategy must be one of BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED, or SPOT_PRICE_CAPACITY_OPTIMIZED."
 }

 validation {
 condition = var.compute_resources.max_vcpus > 0
 error_message = "compute_resources.max_vcpus must be greater than 0."
 }
}

###############################################################################
# Compute environment — optional EKS backing / update policy
###############################################################################

variable "eks_configuration" {
 description = <<EOT
Optional Amazon EKS cluster that backs the compute environment (EKS-on-Batch).
Leave null (default) for ECS-backed Fargate/EC2 compute. When set, wire the EKS
cluster ARN from tf_mod_aws_eks.

 - eks_cluster_arn: ARN of the EKS cluster.
 - kubernetes_namespace: namespace AWS Batch manages pods in.
EOT
 type = object({
 eks_cluster_arn = string
 kubernetes_namespace = string
 })
 default = null
}

variable "update_policy" {
 description = <<EOT
Optional infrastructure-update policy controlling how running jobs are handled
when the compute environment is updated in place. Leave null (default) for the
provider's standard replace-on-update behavior.

 - job_execution_timeout_minutes: minutes to wait for jobs on update.
 - terminate_jobs_on_update: terminate running jobs on update (default
 false — drain rather than kill).
EOT
 type = object({
 job_execution_timeout_minutes = optional(number, 30)
 terminate_jobs_on_update = optional(bool, false)
 })
 default = null
}

###############################################################################
# Job queue
###############################################################################

variable "job_queue" {
 description = <<EOT
The job queue bound to this compute environment. Jobs are submitted to the queue,
which dispatches them to the attached compute environment(s) by priority.

 - name: queue name (required).
 - priority: higher value = higher scheduling priority
 (default 1).
 - state: ENABLED (default) | DISABLED.
 - scheduling_policy_arn: bind an EXISTING fair-share policy by ARN. Leave
 null to auto-bind the policy this module creates
 (var.scheduling_policy), if any.
 - compute_environment_order: explicit ordered list of compute environments
 ({ compute_environment = <arn>, order = <n> }).
 Leave empty (default) to bind this module's
 compute environment at order 0.
 - job_state_time_limit_action: actions taken when a job sits too long in a
 state (e.g. cancel RUNNABLE jobs stuck on
 capacity).
 - tags: extra tags merged over module tags.
EOT
 type = object({
 name = string
 priority = optional(number, 1)
 state = optional(string, "ENABLED")
 scheduling_policy_arn = optional(string)
 compute_environment_order = optional(list(object({
 compute_environment = string
 order = number
 })), [])
 job_state_time_limit_action = optional(list(object({
 action = string
 max_time_seconds = number
 reason = string
 state = string
 })), [])
 tags = optional(map(string), {})
 })

 validation {
 condition = contains(["ENABLED", "DISABLED"], var.job_queue.state)
 error_message = "job_queue.state must be either \"ENABLED\" or \"DISABLED\"."
 }

 validation {
 condition = var.job_queue.priority >= 0
 error_message = "job_queue.priority must be a non-negative integer."
 }

 validation {
 condition = alltrue([
 for a in var.job_queue.job_state_time_limit_action: contains(["CANCEL"], a.action)
 ])
 error_message = "Each job_state_time_limit_action.action must be \"CANCEL\"."
 }
}

###############################################################################
# Job definition
###############################################################################

variable "job_definition" {
 description = <<EOT
The container/Fargate job definition registered for this pipeline. Updating any
field registers a NEW revision (job definitions are immutable per revision).
container_properties is supplied as a typed object and rendered to the JSON the
API expects — no untyped escape hatch. SECURE DEFAULTS: a read-only root
filesystem, no public IP, distinct execution_role_arn (image pull / log push)
and job_role_arn (in-container AWS access), and awslogs logging on.

 - name: job-definition name (required).
 - type: "container" (default) | "multinode".
 - platform_capabilities: ["FARGATE"] (default) or ["EC2"].
 - propagate_tags: copy job-definition tags to the ECS task
 (default true).
 - scheduling_priority: priority within a fair-share queue (0-9999).
 - parameters: default parameter substitutions.
 - deregister_on_new_revision: deregister the prior revision on change
 (default true).
 - retry_strategy: attempts + evaluate_on_exit conditions.
 - timeout: attempt_duration_seconds (>= 60).
 - container_properties: the typed container spec (see below).

container_properties:
 - image: container image URI (required; wire from
 tf_mod_aws_ecr).
 - command: container command override.
 - execution_role_arn: task execution role (ECR pull, log push).
 - job_role_arn: role assumed by the container (least-privilege).
 - vcpu: VCPU resource requirement (default "0.25").
 - memory: MEMORY (MiB) resource requirement (default "512").
 - gpu: GPU resource requirement (EC2 only).
 - environment: plain environment variables (name => value). Do
 NOT place secrets here — use secrets.
 - secrets: name => Secrets Manager / SSM Parameter ARN.
 - user: non-root user to run as (recommended).
 - privileged: run privileged (default false).
 - readonly_root_filesystem: read-only root fs (default true — secure).
 - assign_public_ip: Fargate public IP (default false — secure).
 - fargate_platform_version: Fargate platform version (default LATEST).
 - runtime_platform: cpu_architecture (X86_64/ARM64) + OS family.
 - ephemeral_storage_size_gib: Fargate ephemeral storage (21-200 GiB).
 - log_configuration: log_driver (default "awslogs") + options +
 secret_options.
 - mount_points / volumes: data volumes incl. encrypted EFS.
 - ulimits: container ulimits.

tags: extra tags merged over module tags for the job definition.
EOT
 type = object({
 name = string
 type = optional(string, "container")
 platform_capabilities = optional(list(string), ["FARGATE"])
 propagate_tags = optional(bool, true)
 scheduling_priority = optional(number)
 parameters = optional(map(string), {})
 deregister_on_new_revision = optional(bool, true)
 retry_strategy = optional(object({
 attempts = optional(number, 1)
 evaluate_on_exit = optional(list(object({
 action = string
 on_exit_code = optional(string)
 on_reason = optional(string)
 on_status_reason = optional(string)
 })), [])
 }))
 timeout = optional(object({
 attempt_duration_seconds = optional(number)
 }))
 container_properties = object({
 image = string
 command = optional(list(string))
 execution_role_arn = optional(string)
 job_role_arn = optional(string)
 vcpu = optional(string, "0.25")
 memory = optional(string, "512")
 gpu = optional(string)
 environment = optional(map(string), {})
 secrets = optional(map(string), {})
 user = optional(string)
 privileged = optional(bool, false)
 readonly_root_filesystem = optional(bool, true)
 assign_public_ip = optional(bool, false)
 fargate_platform_version = optional(string)
 runtime_platform = optional(object({
 cpu_architecture = optional(string, "X86_64")
 operating_system_family = optional(string, "LINUX")
 }))
 ephemeral_storage_size_gib = optional(number)
 log_configuration = optional(object({
 log_driver = optional(string, "awslogs")
 options = optional(map(string), {})
 secret_options = optional(map(string), {})
 }), {})
 mount_points = optional(list(object({
 source_volume = string
 container_path = string
 read_only = optional(bool)
 })), [])
 volumes = optional(list(object({
 name = string
 host_source_path = optional(string)
 efs_volume_configuration = optional(object({
 file_system_id = string
 root_directory = optional(string)
 transit_encryption = optional(string, "ENABLED")
 transit_encryption_port = optional(number)
 access_point_id = optional(string)
 iam = optional(string)
 }))
 })), [])
 ulimits = optional(list(object({
 name = string
 soft_limit = number
 hard_limit = number
 })), [])
 })
 tags = optional(map(string), {})
 })

 validation {
 condition = contains(["container", "multinode"], var.job_definition.type)
 error_message = "job_definition.type must be either \"container\" or \"multinode\"."
 }

 validation {
 condition = alltrue([
 for c in var.job_definition.platform_capabilities: contains(["FARGATE", "EC2"], c)
 ])
 error_message = "Each job_definition.platform_capabilities entry must be \"FARGATE\" or \"EC2\"."
 }

 validation {
 condition = var.job_definition.scheduling_priority == null || try(var.job_definition.scheduling_priority >= 0 && var.job_definition.scheduling_priority <= 9999, false)
 error_message = "job_definition.scheduling_priority must be between 0 and 9999."
 }

 validation {
 condition = try(var.job_definition.timeout.attempt_duration_seconds, null) == null || try(var.job_definition.timeout.attempt_duration_seconds >= 60, false)
 error_message = "job_definition.timeout.attempt_duration_seconds must be at least 60 seconds."
 }
}

###############################################################################
# Optional fair-share scheduling policy
###############################################################################

variable "scheduling_policy" {
 description = <<EOT
Optional fair-share scheduling policy created by this module and auto-bound to the
job queue (unless job_queue.scheduling_policy_arn overrides it). Leave null
(default) for first-in-first-out scheduling by queue priority.

 - name: scheduling-policy name (required when set).
 - fair_share_policy: optional fair-share tuning:
 - compute_reservation: % of queue vCPUs reserved for unused fair-share
 identifiers (0-99).
 - share_decay_seconds: window over which prior usage decays (0-604800).
 - share_distribution: per-identifier weight factors (lower weight = more
 vCPUs); set of { share_identifier, weight_factor }.
 - tags: extra tags merged over module tags.
EOT
 type = object({
 name = string
 fair_share_policy = optional(object({
 compute_reservation = optional(number)
 share_decay_seconds = optional(number)
 share_distribution = optional(list(object({
 share_identifier = string
 weight_factor = optional(number)
 })), [])
 }))
 tags = optional(map(string), {})
 })
 default = null
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags assigned to every taggable resource created by this module (the
compute environment, job queue, job definition, scheduling policy, and EC2
resources launched by managed compute). These merge with provider-level
default_tags; resource tags win on key conflict. Per-resource tags supplied
inside the job_queue / job_definition / scheduling_policy / compute_resources
objects merge over these. The computed tags_all output reflects the merged set
for the compute environment.
EOT
 type = map(string)
 default = {}
}
