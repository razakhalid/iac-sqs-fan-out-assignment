# outputs.tf
output "input_bucket_name" {
  value = aws_s3_bucket.input_bucket.id
}

output "output_bucket_name" {
  value = aws_s3_bucket.output_bucket.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.image_topic.arn
}