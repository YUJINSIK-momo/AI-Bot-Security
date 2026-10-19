# WAF 속도 규칙에 걸린 수가 기준을 넘으면 SNS 로 알린다(bot-defense 템플릿) — 사람이 안 봐도 도는 감시.
# waf-alb-count.tf 와 함께 쓴다. SNS → Slack 은 「Amazon Q Developer in chat applications」(옛 AWS Chatbot)로 잇는다.
# 경보 하나는 월 $0.10 안팎이다(CloudWatch 요금).

variable "aws_region" {
  type        = string
  description = "웹 ACL 이 있는 리전(지표 차원 Region)."
}

variable "alarm_sns_topic_arn" {
  type        = string
  description = "알림을 받을 SNS 주제."
}

variable "api_rate_alarm_threshold" {
  type        = number
  default     = 100
  description = "5분 동안 api-rate 규칙에 걸린 요청이 이만큼 넘으면 알린다."
}

resource "aws_cloudwatch_metric_alarm" "api_rate_counted" {
  alarm_name        = "${var.waf_name}-api-rate"
  alarm_description = "bot-defense: /api 속도 규칙에 걸린 요청이 늘었다 — log-watch 스킬로 누가 무엇을 부르는지 본다."
  namespace         = "AWS/WAFV2"
  metric_name       = "CountedRequests"

  dimensions = {
    WebACL = var.waf_name
    Region = var.aws_region
    Rule   = "${var.waf_name}-api-rate"
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.api_rate_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = [var.alarm_sns_topic_arn]
}
