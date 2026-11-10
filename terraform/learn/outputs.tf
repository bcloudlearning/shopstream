output "S3_bucket_name" {
  value = aws_s3_bucket.learn.id
}

output "instance_id" {
  value = aws_instance.learn.id
}

output "ami_name" {
  value = data.aws_ami.al2023_arm.name
}