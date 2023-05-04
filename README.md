# sample-ecs-blue-green
ECS Blue/Green deployment with CodePipeline

## How to Use

Prepare `terraform.tfvars` file. See `variables.tf`.

- `terraform init`
- `terraform plan`
- `terraform apply`

Zip your application code as `code.zip` and upload to the source bucket. See https://github.com/waldemarbautista/simple-flask.

## Known Issues

- After the first run of the pipeline, Terraform should no longer manage the ECS service. Doing `terraform apply` will produce an error.
- CodePipeline is using polling for now.