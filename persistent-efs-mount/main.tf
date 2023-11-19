module "networking" {
  source    = "./modules/networking"
  namespace = var.namespace
}

module "ssh-key" {
  source    = "./modules/ssh-key"
  namespace = var.namespace
}

module "ec2" {
  source    = "./modules/ec2"
  namespace = var.namespace
  vpc       = module.networking.vpc
  sg_efs_id = module.networking.sg_efs_id
  sg_ssh_id = module.networking.sg_ssh_id
  key_name  = module.ssh-key.key_name
}

