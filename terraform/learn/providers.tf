provider "aws" {
  region  = "ap-south-2"
  profile = "shopstream"
  default_tags {
    tags = {
      project   = "shopstream"
      stage     = "2"
      owner     = "bharath"
      managedby = "Terraform"
    }
  }
}