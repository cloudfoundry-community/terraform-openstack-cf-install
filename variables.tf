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
  default = "v1.1.3"
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
