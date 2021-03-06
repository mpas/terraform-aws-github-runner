resource "aws_lambda_function" "scale_up" {
  filename                       = local.lambda_zip
  source_code_hash               = filebase64sha256(local.lambda_zip)
  function_name                  = "${var.environment}-scale-up"
  role                           = aws_iam_role.scale_up.arn
  handler                        = "index.scaleUp"
  runtime                        = "nodejs12.x"
  timeout                        = var.lambda_timeout_scale_up
  reserved_concurrent_executions = 1
  tags                           = local.tags

  environment {
    variables = {
      ENABLE_ORGANIZATION_RUNNERS = var.enable_organization_runners
      RUNNER_EXTRA_LABELS         = var.runner_extra_labels
      GITHUB_APP_KEY_BASE64       = var.github_app.key_base64
      GITHUB_APP_ID               = var.github_app.id
      GITHUB_APP_CLIENT_ID        = var.github_app.client_id
      GITHUB_APP_CLIENT_SECRET    = var.github_app.client_secret
      SUBNET_IDS                  = join(",", var.subnet_ids)
      LAUNCH_TEMPLATE_NAME        = aws_launch_template.runner.name
      LAUNCH_TEMPLATE_VERSION     = aws_launch_template.runner.latest_version
      ENVIRONMENT                 = var.environment
    }
  }
}

resource "aws_lambda_event_source_mapping" "scale_up" {
  event_source_arn = var.sqs_build_queue.arn
  function_name    = aws_lambda_function.scale_up.arn
}

resource "aws_lambda_permission" "scale_runners_lambda" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_up.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = var.sqs_build_queue.arn
}

resource "aws_iam_role" "scale_up" {
  name               = "${var.environment}-action-scale-up-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "scale_up" {
  name = "${var.environment}-lambda-scale-up-policy"
  role = aws_iam_role.scale_up.name

  policy = templatefile("${path.module}/policies/lambda-scale-up.json", {
    arn_runner_instance_role = aws_iam_role.runner.arn
    sqs_arn                  = var.sqs_build_queue.arn
  })
}
