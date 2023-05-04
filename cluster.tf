data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4.0.1"

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 8)]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.3.2"

  domain_name = "${local.domain_prefix}.${local.zone_name}"
  zone_id     = local.zone_id
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.6.0"

  name = "${local.name}-alb"

  subnets = module.vpc.public_subnets
  vpc_id  = module.vpc.vpc_id

  target_groups = [
    {
      name             = "blue"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
    },
    {
      name             = "green"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
    }
  ]

  http_tcp_listeners = [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  https_listeners = [
    {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm.acm_certificate_arn
    }
  ]

  security_group_rules = {
    ingress_all_http = {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_all_https = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

module "route53_records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "2.10.2"

  zone_name = local.zone_name

  records = [
    {
      name = local.domain_prefix
      type = "A"
      alias = {
        name    = module.alb.lb_dns_name
        zone_id = module.alb.lb_zone_id
      }
    }
  ]
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.0.1"

  cluster_name = "${local.name}-ecs"

  cluster_settings = {
    name  = "containerInsights"
    value = "disabled"
  }

  services = {
    web = {
      container_definitions = {
        web = {
          image = "nginx"
          port_mappings = [
            {
              containerPort = 80
              protocol      = "tcp"
            }
          ]
          essential = true

          readonly_root_filesystem = false
        }
      }

      deployment_controller = {
        type = "CODE_DEPLOY"
      }

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_group_arns[0]
          container_name   = "web"
          container_port   = 80
        }
      }

      subnet_ids = module.vpc.private_subnets
      security_group_rules = {
        alb_ingress_80 = {
          type                     = "ingress"
          from_port                = 80
          to_port                  = 80
          protocol                 = "tcp"
          source_security_group_id = module.alb.security_group_id
        }
        egress_all = {
          type        = "egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "5.9.0"

  identifier = "${local.name}-rds"

  engine         = "mariadb"
  engine_version = "10.6"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  username          = "admin"

  create_db_option_group    = false
  create_db_parameter_group = false

  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group_rds.security_group_id]
}

module "security_group_rds" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.17.2"

  name   = "${local.name}-security-group-rds"
  vpc_id = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.ecs.services["web"].security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
}