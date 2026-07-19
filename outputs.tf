###############################################################################
# Primary outputs (id + arn) — compute environment (keystone)
###############################################################################

output "id" {
 description = "The compute environment id (its ARN; AWS Batch uses the ARN as the id)."
 value = aws_batch_compute_environment.this.id
}

output "arn" {
 description = <<EOT
The ARN of the compute environment (cross-resource reference type:
arn:aws:batch:<region>:<account>:compute-environment/<name>). Consumed by IAM
policies, monitoring, and job-queue compute_environment_order bindings.
EOT
 value = aws_batch_compute_environment.this.arn
}

output "name" {
 description = "The name of the compute environment (generated when name/name_prefix are null)."
 value = aws_batch_compute_environment.this.name
}

output "ecs_cluster_arn" {
 description = "ARN of the underlying Amazon ECS cluster that backs the compute environment."
 value = aws_batch_compute_environment.this.ecs_cluster_arn
}

output "status" {
 description = "Current status of the compute environment (e.g. CREATING, VALID)."
 value = aws_batch_compute_environment.this.status
}

###############################################################################
# Job queue
###############################################################################

output "job_queue_id" {
 description = "The job queue id (identical to its ARN; sourced from arn since the provider deprecated the separate id attribute)."
 value = aws_batch_job_queue.this.arn
}

output "job_queue_arn" {
 description = "ARN of the job queue. Consumed by job submission (SubmitJob) and EventBridge/Step Functions targets."
 value = aws_batch_job_queue.this.arn
}

output "job_queue_name" {
 description = "Name of the job queue."
 value = aws_batch_job_queue.this.name
}

###############################################################################
# Job definition
###############################################################################

output "job_definition_arn" {
 description = <<EOT
ARN of the job definition's current revision
(arn:aws:batch:<region>:<account>:job-definition/<name>:<revision>). Consumed by
job submission and EventBridge targets. Updating the definition registers a new
revision and changes this ARN.
EOT
 value = aws_batch_job_definition.this.arn
}

output "job_definition_name" {
 description = "Name of the job definition."
 value = aws_batch_job_definition.this.name
}

output "job_definition_revision" {
 description = "Current revision number of the job definition (increments on every change)."
 value = aws_batch_job_definition.this.revision
}

###############################################################################
# Optional scheduling policy
###############################################################################

output "scheduling_policy_arn" {
 description = "ARN of the fair-share scheduling policy when created by this module; null otherwise. Bound to the job queue."
 value = try(aws_batch_scheduling_policy.this["this"].arn, null)
}

output "scheduling_policy_name" {
 description = "Name of the fair-share scheduling policy when created; null otherwise."
 value = try(aws_batch_scheduling_policy.this["this"].name, null)
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the compute environment, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_batch_compute_environment.this.tags_all
}
