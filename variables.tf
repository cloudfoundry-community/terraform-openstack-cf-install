variable "auth_url" {}
variable "tenant_name" {}
variable "tenant_id" {}
variable "username" {}
variable "password" {}
variable "key_path" {}
variable "public_key_path" {}
variable "floating_ip_pool" {}
variable "network_external_id" {}
variable "region" {
  default = "RegionOne"
}
variable "network" {
	default = "192.168"
}
variable "cf_admin_pass" {
  default = "c1oudc0wc1oudc0w"
}

variable "install_docker_services" {
  default = "false"
}

variable "cf_domain" {
  default = "XIP"
}

variable "cf_boshworkspace_version" {
  default = "v1.1.7"
}

variable "cf_size" {
  default = "tiny"
}

variable "image_name" {
  default = "ubuntu-14.04"
}

variable "flavor_name" {
  default = "m1.medium"
}

variable "http_proxy" {
  default = ""
}
variable "https_proxy" {
  default = ""
}

variable "deployment_size" {
  default = "small"
}

variable "cf_release_version" {
  default = "207"
}

variable backbone_z1_count {
    default = {
        small  = "1"
        med    = "2"
        med-ha = "1"
        big-ha = "2"
    }
}
variable api_z1_count {
    default = {
        small  = "1"
        med    = "2"
        med-ha = "1"
        big-ha = "2"
    }
}
variable services_z1_count {
    default = {
        small  = "1"
        med    = "1"
        med-ha = "1"
        big-ha = "1"
    }
}
variable health_z1_count {
    default = {
        small  = "1"
        med    = "1"
        med-ha = "1"
        big-ha = "1"
    }
}
variable runner_z1_count {
    default = {
        small  = "1"
        med    = "2"
        med-ha = "1"
        big-ha = "3"
    }
}

variable backbone_z2_count {
    default = {
        small  = "0"
        med    = "0"
        med-ha = "1"
        big-ha = "2"
    }
}
variable api_z2_count {
    default = {
        small  = "0"
        med    = "0"
        med-ha = "1"
        big-ha = "2"
    }
}
variable services_z2_count {
    default = {
        small  = "0"
        med    = "0"
        med-ha = "1"
        big-ha = "2"
    }
}
variable health_z2_count {
    default = {
        small  = "0"
        med    = "0"
        med-ha = "1"
        big-ha = "1"
    }
}
variable runner_z2_count {
    default = {
        small  = "0"
        med    = "0"
        med-ha = "1"
        big-ha = "3"
    }
}
