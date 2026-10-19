# ALB 앞에 AWS WAF 웹 ACL 을 「세기만(Count)」 으로 붙인다(bot-defense 템플릿).
# 막지 않고 1~2주 지켜본 뒤, 규칙별로 사람이 Block 으로 바꾼다.
#
# 쓰는 법: 소비 저장소의 Terraform 폴더로 복사하고 이름 · 변수를 그 저장소 관례에 맞춘다. plan 은 PR 에 붙이고, apply 는 사람이 한다.
# 비용(2026-10 확인, 바뀔 수 있음): 웹 ACL 월 $5 + 규칙 3개 월 $3 + 요청 100만 건당 $0.60 + Bot Control 일반 월 $10(월 1천만 요청 포함).
# 로그 전달 권한: WAF 가 CloudWatch Logs 리소스 정책을 만든다. 적용하는 사람에게 logs:PutResourcePolicy · logs:DescribeResourcePolicies 가
#   있어야 하고, 리전당 리소스 정책 수 상한에 걸리면 기존 정책에 합친다(https://docs.aws.amazon.com/waf/latest/developerguide/logging-cw-logs.html).

variable "waf_name" {
  type        = string
  description = "웹 ACL 이름. 로그 그룹은 aws-waf-logs-<이름> 이 된다."
}

variable "alb_arn" {
  type        = string
  description = "WAF 를 붙일 인터넷용 ALB 의 ARN."
}

variable "api_path_prefix" {
  type        = string
  default     = "/api/"
  description = "속도 규칙을 걸 경로의 앞부분."
}

variable "api_rate_limit" {
  type        = number
  default     = 1000
  description = "IP 하나가 5분 동안 api_path_prefix 로 보낼 수 있는 요청 수. 사람이 많이 쓸 때 잰 값의 5배 이상으로 둔다."
}

variable "waf_log_retention_days" {
  type    = number
  default = 30
}

resource "aws_wafv2_web_acl" "bot_defense" {
  name        = var.waf_name
  description = "bot-defense — Count 모드로 시작"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 알려진 나쁜 IP(봇넷 · 정찰). 세기만 한다.
  rule {
    name     = "ip-reputation"
    priority = 10

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.waf_name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # API 경로에 IP 당 속도 규칙. 세기만 한다.
  rule {
    name     = "api-rate"
    priority = 20

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit              = var.api_rate_limit
        aggregate_key_type = "IP"
        # 최근 aws 프로바이더에서 지원한다. 낮은 버전이면 이 줄을 지운다(기본 5분).
        evaluation_window_sec = 300

        scope_down_statement {
          byte_match_statement {
            search_string         = var.api_path_prefix
            positional_constraint = "STARTS_WITH"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.waf_name}-api-rate"
      sampled_requests_enabled   = true
    }
  }

  # 이름을 밝히는 봇 · AI 범주에 라벨을 붙인다(bot:category:ai 등). 세기만 한다.
  rule {
    name     = "bot-control"
    priority = 30

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesBotControlRuleSet"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.waf_name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.waf_name
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.bot_defense.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  # WAF 로그 그룹 이름은 aws-waf-logs- 로 시작해야 한다.
  name              = "aws-waf-logs-${var.waf_name}"
  retention_in_days = var.waf_log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "bot_defense" {
  resource_arn            = aws_wafv2_web_acl.bot_defense.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # 로그에 남기지 않을 머리.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.bot_defense.arn
}

output "waf_log_group_name" {
  value = aws_cloudwatch_log_group.waf.name
}
