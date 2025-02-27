resource "random_password" "worker_pwd" {
  length           = 12
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "tencentcloud_kubernetes_cluster" "cluster" {
  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  cluster_cidr                    = var.cluster_cidr
  cluster_os                      = var.cluster_os
  cluster_internet                = var.cluster_public_access
  cluster_internet_security_group = var.cluster_public_access ? var.cluster_security_group_id : null
  cluster_intranet                = var.cluster_private_access
  cluster_intranet_subnet_id      = var.cluster_private_access ? var.cluster_private_access_subnet_id : null
  vpc_id                          = var.vpc_id
  service_cidr                    = var.cluster_service_cidr

  worker_config {
    availability_zone          = var.available_zone
    count                      = var.worker_count
    instance_type              = var.worker_instance_type
    subnet_id                  = var.intranet_subnet_id
    security_group_ids         = [var.node_security_group_id]
    enhanced_monitor_service   = var.enhanced_monitor_service
    public_ip_assigned         = true
    internet_max_bandwidth_out = var.worker_bandwidth_out
    # check the internal message on your account message center if needed
    password = random_password.worker_pwd.result
  }

  event_persistence {
    enabled                    = var.enable_event_persistence
    delete_event_log_and_topic = var.event_log_topic_id == null
    log_set_id                 = var.event_log_set_id
    topic_id                   = var.event_log_topic_id
  }

  cluster_audit {
    enabled                    = var.enable_cluster_audit_log
    delete_audit_log_and_topic = var.cluster_audit_log_topic_id == null
    log_set_id                 = var.cluster_audit_log_set_id
    topic_id                   = var.cluster_audit_log_topic_id
  }

  tags = var.tags
}


resource "tencentcloud_kubernetes_addon_attachment" "this" {
  # Not supported on outposts
  for_each = var.cluster_addons

  cluster_id = tencentcloud_kubernetes_cluster.cluster.id
  name       = try(each.value.name, each.key)

  version      = try(each.value.version, null)
  values       = try(each.value.values, null)
  request_body = try(each.value.request_body, null)


  depends_on = [
    tencentcloud_kubernetes_node_pool.this
  ]
}

resource "tencentcloud_kubernetes_node_pool" "this" {
  for_each                 = var.self_managed_node_groups
  name                     = try(each.value.name, each.key)
  cluster_id               = tencentcloud_kubernetes_cluster.cluster.id
  max_size                 = try(each.value.max_size, each.value.min_size, 1)
  min_size                 = try(each.value.min_size, each.value.max_size, 1)
  vpc_id                   = var.vpc_id
  subnet_ids               = try(each.value.subnet_ids, [var.intranet_subnet_id])
  retry_policy             = try(each.value.retry_policy, null)
  desired_capacity         = try(each.value.desired_capacity, null)
  enable_auto_scale        = try(each.value.enable_auto_scale, null)
  multi_zone_subnet_policy = try(each.value.multi_zone_subnet_policy, null)
  node_os                  = try(each.value.node_os, var.cluster_os)
  delete_keep_instance     = try(each.value.delete_keep_instance, false)

  dynamic "auto_scaling_config" {
    for_each = try(each.value.auto_scaling_config, null)
    content {
      instance_type      = try(auto_scaling_config.value.instance_type, var.worker_instance_type, null)
      system_disk_type   = try(auto_scaling_config.value.system_disk_type, "CLOUD_PREMIUM")
      system_disk_size   = try(auto_scaling_config.value.system_disk_size, 50)
      security_group_ids = try(auto_scaling_config.value.security_group_ids, null)

      internet_charge_type       = try(auto_scaling_config.value.internet_charge_type, "TRAFFIC_POSTPAID_BY_HOUR")
      internet_max_bandwidth_out = try(auto_scaling_config.value.internet_max_bandwidth_out, 10)
      public_ip_assigned         = try(auto_scaling_config.value.public_ip_assigned, false)
      password                   = try(auto_scaling_config.value.password, random_password.worker_pwd.result, null)
      enhanced_security_service  = try(auto_scaling_config.value.enhanced_security_service, true)
      enhanced_monitor_service   = try(auto_scaling_config.value.enhanced_monitor_service, true)
      host_name                  = try(auto_scaling_config.value.host_name, null)
      host_name_style            = try(auto_scaling_config.value.host_name_style, null)

      dynamic "data_disk" {
        for_each = try(auto_scaling_config.value.data_disk, null)
        content {
          disk_type = try(data_disk.value.disk_type, "CLOUD_PREMIUM")
          disk_size = try(data_disk.value.disk_size, 50)
        }
      }
    }
  }

  labels = try(each.value.labels, null)

  dynamic "taints" {
    for_each = try(each.value.taints, null)
    content {
      key    = try(taints.value.key, null)
      value  = try(taints.value.value, null)
      effect = try(taints.value.effect, null)
    }
  }

  dynamic "node_config" {
    for_each = try(each.value.node_config, null)
    content {
      extra_args = try(node_config.value.extra_args, null)
    }
  }
}

resource "tencentcloud_kubernetes_serverless_node_pool" "this" {
  for_each   = var.self_managed_serverless_node_groups
  name       = try(each.value.name, each.key)
  cluster_id = tencentcloud_kubernetes_cluster.cluster.id
  dynamic "serverless_nodes" {
    for_each = try(each.value.serverless_nodes, null)
    content {
      display_name = try(serverless_nodes.value.display_name, null)
      subnet_id    = try(serverless_nodes.value.subnet_id, null)
    }
  }
  security_group_ids = try(each.value.security_group_ids, null)
  labels             = try(each.value.labels, null)
}