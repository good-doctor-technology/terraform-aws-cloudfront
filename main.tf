locals {
  create_origin_access_identity  = var.create_origin_access_identity && length(keys(var.origin_access_identities)) > 0
  create_origin_access_control   = var.create_origin_access_control && length(keys(var.origin_access_control)) > 0
  create_response_headers_policy = var.create_response_headers_policy && length(keys(var.response_headers_policy)) > 0
}

resource "aws_cloudfront_response_headers_policy" "this" {
  for_each = local.create_response_headers_policy ? var.response_headers_policy : {}

  name    = try(each.value.name, each.key)
  comment = try(each.value.comment, null)

  dynamic "cors_config" {
    for_each = try(each.value.cors_config, null) == null ? [] : [each.value.cors_config]

    content {
      origin_override                  = try(cors_config.value.origin_override, null)
      access_control_allow_credentials = try(cors_config.value.access_control_allow_credentials, null)
      access_control_max_age_sec       = try(cors_config.value.access_control_max_age_sec, null)

      dynamic "access_control_allow_headers" {
        for_each = try(cors_config.value.access_control_allow_headers, null) == null ? [] : [true]

        content {
          items = cors_config.value.access_control_allow_headers
        }
      }

      dynamic "access_control_allow_methods" {
        for_each = try(cors_config.value.access_control_allow_methods, null) == null ? [] : [true]

        content {
          items = cors_config.value.access_control_allow_methods
        }
      }

      dynamic "access_control_allow_origins" {
        for_each = try(cors_config.value.access_control_allow_origins, null) == null ? [] : [true]

        content {
          items = cors_config.value.access_control_allow_origins
        }
      }

      dynamic "access_control_expose_headers" {
        for_each = try(cors_config.value.access_control_expose_headers, null) == null ? [] : [true]

        content {
          items = cors_config.value.access_control_expose_headers
        }
      }
    }
  }

  dynamic "custom_headers_config" {
    for_each = try(each.value.custom_headers_config, null) == null ? [] : [true]
    content {
      dynamic "items" {
        for_each = try(each.value.custom_headers_config, [])
        content {
          header   = items.value.header
          value    = items.value.value
          override = items.value.override
        }
      }
    }
  }

  dynamic "remove_headers_config" {
    for_each = try(each.value.remove_headers_config, null) == null ? [] : [1]
    content {
      dynamic "items" {
        for_each = try(each.value.remove_headers_config, [])

        content {
          header = items.value
        }
      }
    }
  }

  dynamic "server_timing_headers_config" {
    for_each = try(each.value.server_timing_headers_config, null) == null ? [] : [each.value.server_timing_headers_config]
    content {
      enabled       = try(server_timing_headers_config.value.enabled, null)
      sampling_rate = try(server_timing_headers_config.value.sampling_rate, null)
    }
  }
}


resource "aws_cloudfront_origin_access_identity" "this" {
  for_each = local.create_origin_access_identity ? var.origin_access_identities : {}

  comment = each.value

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.create_origin_access_control ? var.origin_access_control : {}

  name = each.key

  description                       = each.value["description"]
  origin_access_control_origin_type = each.value["origin_type"]
  signing_behavior                  = each.value["signing_behavior"]
  signing_protocol                  = each.value["signing_protocol"]
}

locals {
  created_response_headers_policy = !local.create_response_headers_policy ? {} : {
    for k, v in var.response_headers_policy : v.name => aws_cloudfront_response_headers_policy.this[k]
  }
}

resource "aws_cloudfront_distribution" "this" {
  count = var.create_distribution ? 1 : 0

  aliases                         = var.aliases
  comment                         = var.comment
  continuous_deployment_policy_id = var.continuous_deployment_policy_id
  default_root_object             = var.default_root_object
  enabled                         = var.enabled
  http_version                    = var.http_version
  is_ipv6_enabled                 = var.is_ipv6_enabled
  price_class                     = var.price_class
  retain_on_delete                = var.retain_on_delete
  staging                         = var.staging
  wait_for_deployment             = var.wait_for_deployment
  web_acl_id                      = var.web_acl_id
  tags                            = var.tags

  dynamic "logging_config" {
    for_each = length(keys(var.logging_config)) == 0 ? [] : [var.logging_config]

    content {
      bucket          = logging_config.value["bucket"]
      prefix          = lookup(logging_config.value, "prefix", null)
      include_cookies = lookup(logging_config.value, "include_cookies", null)
    }
  }

  dynamic "origin" {
    for_each = var.origin

    content {
      domain_name              = origin.value.domain_name
      origin_id                = lookup(origin.value, "origin_id", origin.key)
      origin_path              = lookup(origin.value, "origin_path", "")
      connection_attempts      = lookup(origin.value, "connection_attempts", null)
      connection_timeout       = lookup(origin.value, "connection_timeout", null)
      origin_access_control_id = lookup(origin.value, "origin_access_control_id", lookup(lookup(aws_cloudfront_origin_access_control.this, lookup(origin.value, "origin_access_control", ""), {}), "id", null))

      dynamic "s3_origin_config" {
        for_each = length(keys(lookup(origin.value, "s3_origin_config", {}))) == 0 ? [] : [lookup(origin.value, "s3_origin_config", {})]

        content {
          origin_access_identity = lookup(s3_origin_config.value, "cloudfront_access_identity_path", lookup(lookup(aws_cloudfront_origin_access_identity.this, lookup(s3_origin_config.value, "origin_access_identity", ""), {}), "cloudfront_access_identity_path", null))
        }
      }

      dynamic "custom_origin_config" {
        for_each = length(lookup(origin.value, "custom_origin_config", "")) == 0 ? [] : [lookup(origin.value, "custom_origin_config", "")]

        content {
          http_port                = custom_origin_config.value.http_port
          https_port               = custom_origin_config.value.https_port
          origin_protocol_policy   = custom_origin_config.value.origin_protocol_policy
          origin_ssl_protocols     = custom_origin_config.value.origin_ssl_protocols
          origin_keepalive_timeout = lookup(custom_origin_config.value, "origin_keepalive_timeout", null)
          origin_read_timeout      = lookup(custom_origin_config.value, "origin_read_timeout", null)
        }
      }

      dynamic "custom_header" {
        for_each = lookup(origin.value, "custom_header", [])

        content {
          name  = custom_header.value.name
          value = custom_header.value.value
        }
      }

      dynamic "origin_shield" {
        for_each = length(keys(lookup(origin.value, "origin_shield", {}))) == 0 ? [] : [lookup(origin.value, "origin_shield", {})]

        content {
          enabled              = origin_shield.value.enabled
          origin_shield_region = origin_shield.value.origin_shield_region
        }
      }
    }
  }

  dynamic "origin_group" {
    for_each = var.origin_group

    content {
      origin_id = lookup(origin_group.value, "origin_id", origin_group.key)

      failover_criteria {
        status_codes = origin_group.value["failover_status_codes"]
      }

      member {
        origin_id = origin_group.value["primary_member_origin_id"]
      }

      member {
        origin_id = origin_group.value["secondary_member_origin_id"]
      }
    }
  }

  dynamic "default_cache_behavior" {
    for_each = [var.default_cache_behavior]
    iterator = i

    content {
      target_origin_id       = i.value["target_origin_id"]
      viewer_protocol_policy = i.value["viewer_protocol_policy"]

      allowed_methods           = lookup(i.value, "allowed_methods", ["GET", "HEAD", "OPTIONS"])
      cached_methods            = lookup(i.value, "cached_methods", ["GET", "HEAD"])
      compress                  = lookup(i.value, "compress", null)
      field_level_encryption_id = lookup(i.value, "field_level_encryption_id", null)
      smooth_streaming          = lookup(i.value, "smooth_streaming", null)
      trusted_signers           = lookup(i.value, "trusted_signers", null)
      trusted_key_groups        = lookup(i.value, "trusted_key_groups", null)

      cache_policy_id            = try(i.value.cache_policy_id, data.aws_cloudfront_cache_policy.this[i.value.cache_policy_name].id, null)
      origin_request_policy_id   = try(i.value.origin_request_policy_id, data.aws_cloudfront_origin_request_policy.this[i.value.origin_request_policy_name].id, null)
      response_headers_policy_id = try(i.value.response_headers_policy_id, data.aws_cloudfront_response_headers_policy.this[i.value.response_headers_policy_name].id, local.created_response_headers_policy[i.value.response_headers_policy_name].id, null)

      realtime_log_config_arn = lookup(i.value, "realtime_log_config_arn", null)

      min_ttl     = lookup(i.value, "min_ttl", null)
      default_ttl = lookup(i.value, "default_ttl", null)
      max_ttl     = lookup(i.value, "max_ttl", null)

      dynamic "forwarded_values" {
        for_each = lookup(i.value, "use_forwarded_values", true) ? [true] : []

        content {
          query_string            = lookup(i.value, "query_string", false)
          query_string_cache_keys = lookup(i.value, "query_string_cache_keys", [])
          headers                 = lookup(i.value, "headers", [])

          cookies {
            forward           = lookup(i.value, "cookies_forward", "none")
            whitelisted_names = lookup(i.value, "cookies_whitelisted_names", null)
          }
        }
      }

      dynamic "lambda_function_association" {
        for_each = lookup(i.value, "lambda_function_association", [])
        iterator = l

        content {
          event_type   = l.key
          lambda_arn   = l.value.lambda_arn
          include_body = lookup(l.value, "include_body", null)
        }
      }

      dynamic "function_association" {
        for_each = lookup(i.value, "function_association", [])
        iterator = f

        content {
          event_type   = f.key
          function_arn = f.value.function_arn
        }
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behavior
    iterator = i

    content {
      path_pattern           = i.value["path_pattern"]
      target_origin_id       = i.value["target_origin_id"]
      viewer_protocol_policy = i.value["viewer_protocol_policy"]

      allowed_methods           = lookup(i.value, "allowed_methods", ["GET", "HEAD", "OPTIONS"])
      cached_methods            = lookup(i.value, "cached_methods", ["GET", "HEAD"])
      compress                  = lookup(i.value, "compress", null)
      field_level_encryption_id = lookup(i.value, "field_level_encryption_id", null)
      smooth_streaming          = lookup(i.value, "smooth_streaming", null)
      trusted_signers           = lookup(i.value, "trusted_signers", null)
      trusted_key_groups        = lookup(i.value, "trusted_key_groups", null)

      cache_policy_id            = try(i.value.cache_policy_id, data.aws_cloudfront_cache_policy.this[i.value.cache_policy_name].id, null)
      origin_request_policy_id   = try(i.value.origin_request_policy_id, data.aws_cloudfront_origin_request_policy.this[i.value.origin_request_policy_name].id, null)
      response_headers_policy_id = try(i.value.response_headers_policy_id, data.aws_cloudfront_response_headers_policy.this[i.value.response_headers_policy_name].id, local.created_response_headers_policy[i.value.response_headers_policy_name].id, null)

      realtime_log_config_arn = lookup(i.value, "realtime_log_config_arn", null)

      min_ttl     = lookup(i.value, "min_ttl", null)
      default_ttl = lookup(i.value, "default_ttl", null)
      max_ttl     = lookup(i.value, "max_ttl", null)

      dynamic "forwarded_values" {
        for_each = lookup(i.value, "use_forwarded_values", true) ? [true] : []

        content {
          query_string            = lookup(i.value, "query_string", false)
          query_string_cache_keys = lookup(i.value, "query_string_cache_keys", [])
          headers                 = lookup(i.value, "headers", [])

          cookies {
            forward           = lookup(i.value, "cookies_forward", "none")
            whitelisted_names = lookup(i.value, "cookies_whitelisted_names", null)
          }
        }
      }

      dynamic "lambda_function_association" {
        for_each = lookup(i.value, "lambda_function_association", [])
        iterator = l

        content {
          event_type   = l.key
          lambda_arn   = l.value.lambda_arn
          include_body = lookup(l.value, "include_body", null)
        }
      }

      dynamic "function_association" {
        for_each = lookup(i.value, "function_association", [])
        iterator = f

        content {
          event_type   = f.key
          function_arn = f.value.function_arn
        }
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn            = lookup(var.viewer_certificate, "acm_certificate_arn", null)
    cloudfront_default_certificate = lookup(var.viewer_certificate, "cloudfront_default_certificate", null)
    iam_certificate_id             = lookup(var.viewer_certificate, "iam_certificate_id", null)

    minimum_protocol_version = lookup(var.viewer_certificate, "minimum_protocol_version", "TLSv1")
    ssl_support_method       = lookup(var.viewer_certificate, "ssl_support_method", null)
  }

  dynamic "custom_error_response" {
    for_each = length(flatten([var.custom_error_response])[0]) > 0 ? flatten([var.custom_error_response]) : []

    content {
      error_code = custom_error_response.value["error_code"]

      response_code         = lookup(custom_error_response.value, "response_code", null)
      response_page_path    = lookup(custom_error_response.value, "response_page_path", null)
      error_caching_min_ttl = lookup(custom_error_response.value, "error_caching_min_ttl", null)
    }
  }

  restrictions {
    dynamic "geo_restriction" {
      for_each = [var.geo_restriction]

      content {
        restriction_type = lookup(geo_restriction.value, "restriction_type", "none")
        locations        = lookup(geo_restriction.value, "locations", [])
      }
    }
  }

  depends_on = [aws_cloudfront_response_headers_policy.this]
}

resource "aws_cloudfront_monitoring_subscription" "this" {
  count = var.create_distribution && var.create_monitoring_subscription ? 1 : 0

  distribution_id = aws_cloudfront_distribution.this[0].id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = var.realtime_metrics_subscription_status
    }
  }
}

data "aws_cloudfront_cache_policy" "this" {
  for_each = toset([for v in concat([var.default_cache_behavior], var.ordered_cache_behavior) : v.cache_policy_name if can(v.cache_policy_name)])

  name = each.key
}

data "aws_cloudfront_origin_request_policy" "this" {
  for_each = toset([for v in concat([var.default_cache_behavior], var.ordered_cache_behavior) : v.origin_request_policy_name if can(v.origin_request_policy_name)])

  name = each.key
}

data "aws_cloudfront_response_headers_policy" "this" {
  for_each = toset([for v in concat([var.default_cache_behavior], var.ordered_cache_behavior) : v.response_headers_policy_name if can(v.response_headers_policy_name) && !local.create_response_headers_policy])

  name = each.key
}
