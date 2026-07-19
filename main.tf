###############################################################################
# Locals — derived bindings and rendered container properties
###############################################################################

locals {
 # Whether the optional fair-share scheduling policy is created by this module.
 create_scheduling_policy = var.scheduling_policy != null

 # The scheduling policy the queue binds to: a caller-supplied ARN wins; else
 # the policy this module creates (if any); else FIFO-by-priority (null).
 job_queue_scheduling_policy_arn = (var.job_queue.scheduling_policy_arn != null
 ? var.job_queue.scheduling_policy_arn
: try(aws_batch_scheduling_policy.this["this"].arn, null))

 # Compute-environment ordering for the queue: an explicit list wins; otherwise
 # bind this module's compute environment at order 0.
 job_queue_compute_environment_order = (length(var.job_queue.compute_environment_order) > 0
 ? var.job_queue.compute_environment_order
: [{ compute_environment = aws_batch_compute_environment.this.arn, order = 0 }])

 # ---- Rendered container_properties JSON --------------------------------- #
 # The provider compares container_properties as normalized JSON. We render the
 # typed object into the API's camelCase shape, omitting keys that are unset so
 # no perpetual diff appears.
 cp = var.job_definition.container_properties
 is_fargate = contains(var.job_definition.platform_capabilities, "FARGATE")

 cp_resource_requirements = concat(local.cp.vcpu != null ? [{ type = "VCPU", value = local.cp.vcpu }]: [],
 local.cp.memory != null ? [{ type = "MEMORY", value = local.cp.memory }]: [],
 local.cp.gpu != null ? [{ type = "GPU", value = local.cp.gpu }]: [],)

 cp_environment = [for k, v in local.cp.environment: { name = k, value = v }]
 cp_secrets = [for k, v in local.cp.secrets: { name = k, valueFrom = v }]

 cp_log_configuration = merge({
 logDriver = local.cp.log_configuration.log_driver
 options = local.cp.log_configuration.options
 },
 length(local.cp.log_configuration.secret_options) > 0 ? {
 secretOptions = [for k, v in local.cp.log_configuration.secret_options: { name = k, valueFrom = v }]
 }: {},)

 cp_mount_points = [for m in local.cp.mount_points: merge({
 sourceVolume = m.source_volume
 containerPath = m.container_path
 },
 m.read_only != null ? { readOnly = m.read_only }: {},)]

 cp_volumes = [for v in local.cp.volumes: merge({ name = v.name },
 v.host_source_path != null ? { host = { sourcePath = v.host_source_path } }: {},
 try(v.efs_volume_configuration, null) != null ? { efsVolumeConfiguration = merge({
 fileSystemId = v.efs_volume_configuration.file_system_id
 transitEncryption = v.efs_volume_configuration.transit_encryption
 },
 try(v.efs_volume_configuration.root_directory, null) != null ? { rootDirectory = v.efs_volume_configuration.root_directory }: {},
 try(v.efs_volume_configuration.transit_encryption_port, null) != null ? { transitEncryptionPort = v.efs_volume_configuration.transit_encryption_port }: {},
 (try(v.efs_volume_configuration.access_point_id, null) != null || try(v.efs_volume_configuration.iam, null) != null) ? {
 authorizationConfig = merge(try(v.efs_volume_configuration.access_point_id, null) != null ? { accessPointId = v.efs_volume_configuration.access_point_id }: {},
 try(v.efs_volume_configuration.iam, null) != null ? { iam = v.efs_volume_configuration.iam }: {},)
 }: {},) }: {},)]

 cp_ulimits = [for u in local.cp.ulimits: {
 name = u.name
 softLimit = u.soft_limit
 hardLimit = u.hard_limit
 }]

 container_properties = jsonencode(merge({
 image = local.cp.image
 resourceRequirements = local.cp_resource_requirements
 privileged = local.cp.privileged
 readonlyRootFilesystem = local.cp.readonly_root_filesystem
 logConfiguration = local.cp_log_configuration
 },
 local.cp.command != null ? { command = local.cp.command }: {},
 local.cp.execution_role_arn != null ? { executionRoleArn = local.cp.execution_role_arn }: {},
 local.cp.job_role_arn != null ? { jobRoleArn = local.cp.job_role_arn }: {},
 local.cp.user != null ? { user = local.cp.user }: {},
 length(local.cp_environment) > 0 ? { environment = local.cp_environment }: {},
 length(local.cp_secrets) > 0 ? { secrets = local.cp_secrets }: {},
 local.is_fargate ? { networkConfiguration = { assignPublicIp = local.cp.assign_public_ip ? "ENABLED": "DISABLED" } }: {},
 local.is_fargate && local.cp.fargate_platform_version != null ? { fargatePlatformConfiguration = { platformVersion = local.cp.fargate_platform_version } }: {},
 try(local.cp.runtime_platform, null) != null ? { runtimePlatform = {
 cpuArchitecture = local.cp.runtime_platform.cpu_architecture
 operatingSystemFamily = local.cp.runtime_platform.operating_system_family
 } }: {},
 local.cp.ephemeral_storage_size_gib != null ? { ephemeralStorage = { sizeInGiB = local.cp.ephemeral_storage_size_gib } }: {},
 length(local.cp_mount_points) > 0 ? { mountPoints = local.cp_mount_points }: {},
 length(local.cp_volumes) > 0 ? { volumes = local.cp_volumes }: {},
 length(local.cp_ulimits) > 0 ? { ulimits = local.cp_ulimits }: {},))
}

###############################################################################
# Compute environment (keystone)
#
# v6 uses name / name_prefix (the legacy compute_environment_name was renamed).
# For MANAGED environments the v6 provider prefers the AWSServiceRoleForBatch
# service-linked role; supply service_role only to override it. compute_resources
# is rendered only for MANAGED environments.
###############################################################################

resource "aws_batch_compute_environment" "this" {
 name = var.name
 name_prefix = var.name_prefix
 type = var.compute_environment_type
 state = var.state
 service_role = var.service_role_arn

 dynamic "compute_resources" {
 for_each = var.compute_environment_type == "MANAGED" ? { this = var.compute_resources }: {}

 content {
 type = compute_resources.value.type
 max_vcpus = compute_resources.value.max_vcpus
 subnets = var.subnet_ids
 security_group_ids = var.security_group_ids
 min_vcpus = compute_resources.value.min_vcpus
 desired_vcpus = compute_resources.value.desired_vcpus
 allocation_strategy = compute_resources.value.allocation_strategy
 bid_percentage = compute_resources.value.bid_percentage
 instance_type = compute_resources.value.instance_types
 instance_role = var.instance_role_arn
 spot_iam_fleet_role = var.spot_iam_fleet_role_arn
 ec2_key_pair = compute_resources.value.ec2_key_pair
 image_id = compute_resources.value.image_id
 placement_group = compute_resources.value.placement_group

 tags = merge(var.tags, compute_resources.value.tags)

 dynamic "ec2_configuration" {
 for_each = { for idx, c in compute_resources.value.ec2_configuration: idx => c }

 content {
 image_id_override = try(ec2_configuration.value.image_id_override, null)
 image_kubernetes_version = try(ec2_configuration.value.image_kubernetes_version, null)
 image_type = try(ec2_configuration.value.image_type, null)
 }
 }

 dynamic "launch_template" {
 for_each = compute_resources.value.launch_template != null ? { this = compute_resources.value.launch_template }: {}

 content {
 launch_template_id = try(launch_template.value.launch_template_id, null)
 launch_template_name = try(launch_template.value.launch_template_name, null)
 version = try(launch_template.value.version, null)
 }
 }
 }
 }

 dynamic "eks_configuration" {
 for_each = var.eks_configuration != null ? { this = var.eks_configuration }: {}

 content {
 eks_cluster_arn = eks_configuration.value.eks_cluster_arn
 kubernetes_namespace = eks_configuration.value.kubernetes_namespace
 }
 }

 dynamic "update_policy" {
 for_each = var.update_policy != null ? { this = var.update_policy }: {}

 content {
 job_execution_timeout_minutes = try(update_policy.value.job_execution_timeout_minutes, 30)
 terminate_jobs_on_update = try(update_policy.value.terminate_jobs_on_update, false)
 }
 }

 tags = var.tags
}

###############################################################################
# Optional fair-share scheduling policy
#
# Guarded via for_each (no count): the "this" key materializes only when the
# caller supplies a scheduling_policy object. The queue auto-binds to it unless
# job_queue.scheduling_policy_arn overrides.
###############################################################################

resource "aws_batch_scheduling_policy" "this" {
 for_each = local.create_scheduling_policy ? { this = var.scheduling_policy }: {}

 name = each.value.name

 dynamic "fair_share_policy" {
 for_each = try(each.value.fair_share_policy, null) != null ? { this = each.value.fair_share_policy }: {}

 content {
 compute_reservation = try(fair_share_policy.value.compute_reservation, null)
 share_decay_seconds = try(fair_share_policy.value.share_decay_seconds, null)

 dynamic "share_distribution" {
 for_each = { for s in try(fair_share_policy.value.share_distribution, []): s.share_identifier => s }

 content {
 share_identifier = share_distribution.value.share_identifier
 weight_factor = try(share_distribution.value.weight_factor, null)
 }
 }
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# Job queue
#
# Binds to this module's compute environment at order 0 by default. A queue that
# is in use by jobs (or referencing an active CE) must be disabled before the
# compute environment can be deleted — see destroy ordering in the README.
###############################################################################

resource "aws_batch_job_queue" "this" {
 name = var.job_queue.name
 priority = var.job_queue.priority
 state = var.job_queue.state
 scheduling_policy_arn = local.job_queue_scheduling_policy_arn

 dynamic "compute_environment_order" {
 for_each = { for ceo in local.job_queue_compute_environment_order: ceo.order => ceo }

 content {
 compute_environment = compute_environment_order.value.compute_environment
 order = compute_environment_order.value.order
 }
 }

 dynamic "job_state_time_limit_action" {
 for_each = { for idx, a in var.job_queue.job_state_time_limit_action: idx => a }

 content {
 action = job_state_time_limit_action.value.action
 max_time_seconds = job_state_time_limit_action.value.max_time_seconds
 reason = job_state_time_limit_action.value.reason
 state = job_state_time_limit_action.value.state
 }
 }

 tags = merge(var.tags, var.job_queue.tags)
}

###############################################################################
# Job definition
#
# Registers a new revision on any change (immutable per revision).
# container_properties is rendered from the typed object in locals above.
###############################################################################

resource "aws_batch_job_definition" "this" {
 name = var.job_definition.name
 type = var.job_definition.type
 platform_capabilities = var.job_definition.platform_capabilities
 propagate_tags = var.job_definition.propagate_tags
 scheduling_priority = var.job_definition.scheduling_priority
 parameters = var.job_definition.parameters
 deregister_on_new_revision = var.job_definition.deregister_on_new_revision

 container_properties = local.container_properties

 dynamic "retry_strategy" {
 for_each = var.job_definition.retry_strategy != null ? { this = var.job_definition.retry_strategy }: {}

 content {
 attempts = try(retry_strategy.value.attempts, null)

 dynamic "evaluate_on_exit" {
 for_each = { for idx, e in try(retry_strategy.value.evaluate_on_exit, []): idx => e }

 content {
 action = evaluate_on_exit.value.action
 on_exit_code = try(evaluate_on_exit.value.on_exit_code, null)
 on_reason = try(evaluate_on_exit.value.on_reason, null)
 on_status_reason = try(evaluate_on_exit.value.on_status_reason, null)
 }
 }
 }
 }

 dynamic "timeout" {
 for_each = var.job_definition.timeout != null ? { this = var.job_definition.timeout }: {}

 content {
 attempt_duration_seconds = try(timeout.value.attempt_duration_seconds, null)
 }
 }

 tags = merge(var.tags, var.job_definition.tags)
}
