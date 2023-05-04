resource "aws_ecr_repository" "this" {
  name = "simple-flask"
}

resource "aws_s3_bucket" "artifact" {
  bucket_prefix = "${local.name}-artifact-bucket"
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "codepipeline" {
  name = "${local.name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com"
            ]
          }
        }
      },
      {
        Action = [
          "ecs:*",
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:BatchGetBuildBatches",
          "codebuild:StartBuildBatch",
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:Abort*",
          "s3:DeleteObject*",
          "s3:GetBucket*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject",
          "s3:PutObjectLegalHold",
          "s3:PutObjectRetention",
          "s3:PutObjectTagging",
          "s3:PutObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.artifact.arn,
          "${aws_s3_bucket.artifact.arn}/*"
        ]
      },
      {
        Action = [
          "s3:GetBucket*",
          "s3:GetObject*",
          "s3:List*"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_codepipeline" "this" {
  name     = "${local.name}-codepipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifact.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket             = aws_s3_bucket.source.bucket
        S3ObjectKey          = "code.zip"
        PollForSourceChanges = true
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.this.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.this.deployment_group_name
        TaskDefinitionTemplateArtifact = "build_output"
        AppSpecTemplateArtifact        = "build_output"
      }
    }
  }
}

resource "aws_s3_bucket" "source" {
  bucket_prefix = "${local.name}-source-bucket"
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "codebuild" {
  name = "${local.name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = ["*"]
      },
      {
        Action = [
          "s3:Abort*",
          "s3:DeleteObject*",
          "s3:GetBucket*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject",
          "s3:PutObjectLegalHold",
          "s3:PutObjectRetention",
          "s3:PutObjectTagging",
          "s3:PutObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.artifact.arn,
          "${aws_s3_bucket.artifact.arn}/*"
        ]
      },
      {
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

locals {
  env_vars = {
    REGISTRY_ID        = "${aws_ecr_repository.this.registry_id}.dkr.ecr.${local.region}.amazonaws.com"
    REPOSITORY_URL     = aws_ecr_repository.this.repository_url
    TASK_ROLE_ARN      = module.ecs.services["web"].task_exec_iam_role_arn
    EXECUTION_ROLE_ARN = module.ecs.services["web"].task_exec_iam_role_arn
    LOG_GROUP          = module.ecs.services["web"].container_definitions["web"].cloudwatch_log_group_name
    LOG_REGION         = local.region
    LOG_STREAM_PREFIX  = "ecs"
    DATABASE_URI       = "mysql://${module.rds.db_instance_username}:${module.rds.db_instance_password}@${module.rds.db_instance_endpoint}/information_schema"
  }
}

resource "aws_codebuild_project" "this" {
  name         = "${local.name}-codebuild"
  service_role = aws_iam_role.codebuild.arn

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    privileged_mode = true
    type            = "LINUX_CONTAINER"

    dynamic "environment_variable" {
      for_each = local.env_vars

      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
  }
}

resource "aws_codedeploy_app" "this" {
  name = "${local.name}-codedeploy"

  compute_platform = "ECS"
}

data "aws_iam_policy" "codedeploy" {
  name = "AWSCodeDeployRoleForECS"
}

resource "aws_iam_role" "codedeploy" {
  name = "${local.name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [data.aws_iam_policy.codedeploy.arn]
}

resource "aws_codedeploy_deployment_group" "this" {
  deployment_group_name = "${local.name}-codedeploy-deployment-group"

  app_name               = aws_codedeploy_app.this.name
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = aws_iam_role.codedeploy.arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = module.ecs.cluster_name
    service_name = module.ecs.services["web"].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = module.alb.https_listener_arns
      }

      target_group {
        name = module.alb.target_group_names[0]
      }

      target_group {
        name = module.alb.target_group_names[1]
      }
    }
  }
}
