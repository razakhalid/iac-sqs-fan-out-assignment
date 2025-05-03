# S3 Bucket for image upload input
resource "aws_s3_bucket_input" {
    bucket = var.input_bucket_name
    force_destroy = true
}

# S3 Bucket for image upload output
resource "aws_s3_bucket_input" {
    bucket = var.output_bucket_name
    force_destroy = true
}

# SNS topic for image upload notifications
resource "aws_sns_topic" "image_upload_notifications_topic" {
    name = "image_upload_notifications_topic"
}

# Policy for S3 to publish to SNS "image_topic_policy" {
    arn = aws_sns_topic.image_topic.arn
 policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.image_topic.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.input_bucket.arn
          }
        }
      }
    ]
  })
}