locals {
  tags = merge(var.tags, {
    Environment = var.environment
  })

  s3_action_runner_url = "s3://${module.runner_binaries.bucket.id}/${module.runner_binaries.runner_distribution_object_key}"
}

resource "random_string" "random" {
  length  = 24
  special = false
  upper   = false
}

resource "aws_sqs_queue" "queued_builds" {
  name                        = "${var.environment}-queued-builds.fifo"
  delay_seconds               = 30
  visibility_timeout_seconds  = 60
  fifo_queue                  = true
  receive_wait_time_seconds   = 10
  content_based_deduplication = true

  tags = var.tags
}

module "webhook" {
  source = "./modules/webhook"

  aws_region  = var.aws_region
  environment = var.environment
  tags        = local.tags

  sqs_build_queue           = aws_sqs_queue.queued_builds
  github_app_webhook_secret = var.github_app.webhook_secret

  lambda_zip     = var.webhook_lambda_zip
  lambda_timeout = var.webhook_lambda_timeout
}

module "runners" {
  source = "./modules/runners"

  aws_region  = var.aws_region
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  environment = var.environment
  tags        = local.tags

  s3_bucket_runner_binaries   = module.runner_binaries.bucket
  s3_location_runner_binaries = local.s3_action_runner_url

  sqs_build_queue                 = aws_sqs_queue.queued_builds
  github_app                      = var.github_app
  enable_organization_runners     = var.enable_organization_runners
  scale_down_schedule_expression  = var.scale_down_schedule_expression
  minimum_running_time_in_minutes = var.minimum_running_time_in_minutes
  runner_extra_labels             = var.runner_extra_labels

  lambda_zip                = var.runners_lambda_zip
  lambda_timeout_scale_up   = var.runners_scale_up_lambda_timeout
  lambda_timeout_scale_down = var.runners_scale_down_lambda_timeout
}

module "runner_binaries" {
  source = "./modules/runner-binaries-syncer"

  aws_region  = var.aws_region
  environment = var.environment
  tags        = local.tags

  distribution_bucket_name = "${var.environment}-dist-${random_string.random.result}"

  lambda_zip     = var.runner_binaries_syncer_lambda_zip
  lambda_timeout = var.runner_binaries_syncer_lambda_timeout
}

resource "aws_resourcegroups_group" "resourcegroups_group" {
  name = "${var.environment}-group"
  resource_query {
    query = templatefile("${path.module}/templates/resource-group.json", {
      environment = var.environment
    })
  }
}
