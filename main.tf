# --- S3 ---
# Input bucket for uploading images
resource "aws_s3_bucket" "input_bucket" {
  bucket = var.input_bucket_name
  force_destroy = true
}

# Output bucket for processed results
resource "aws_s3_bucket" "output_bucket" {
  bucket = var.output_bucket_name
  force_destroy = true
}

# --- SNS ---
# SNS Topic for image notifications
resource "aws_sns_topic" "image_topic" {
  name = "image-processing-topic"
}

# Policy to allow S3 to publish to SNS
resource "aws_sns_topic_policy" "image_topic_policy" {
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

# --- SQS Queues ---
# Queue for thumbnail generation
resource "aws_sqs_queue" "thumbnail_queue" {
  name = "thumbnail-queue"
  visibility_timeout_seconds = 300  # Match Lambda timeout
}

resource "aws_sqs_queue" "thumbnail_dlq" {
  name = "thumbnail-dlq"
}

# Queue for image recognition
resource "aws_sqs_queue" "recognition_queue" {
  name = "recognition-queue"
  visibility_timeout_seconds = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.recognition_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "recognition_dlq" {
  name = "recognition-dlq"
}

# Queue for metadata processing
resource "aws_sqs_queue" "metadata_queue" {
  name = "metadata-queue"
  visibility_timeout_seconds = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.metadata_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "metadata_dlq" {
  name = "metadata-dlq"
}

# --- SNS Subscriptions ---
# Subscribe thumbnail queue to SNS topic
resource "aws_sns_topic_subscription" "thumbnail_subscription" {
  topic_arn = aws_sns_topic.image_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.thumbnail_queue.arn
}

# Subscribe recognition queue to SNS topic
resource "aws_sns_topic_subscription" "recognition_subscription" {
  topic_arn = aws_sns_topic.image_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.recognition_queue.arn
}

# Subscribe metadata queue to SNS topic
resource "aws_sns_topic_subscription" "metadata_subscription" {
  topic_arn = aws_sns_topic.image_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.metadata_queue.arn
}

# --- SQS Policies ---
# Policy allowing SNS to send messages to thumbnail queue
resource "aws_sqs_queue_policy" "thumbnail_queue_policy" {
  queue_url = aws_sqs_queue.thumbnail_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.thumbnail_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.image_topic.arn
          }
        }
      }
    ]
  })
}

# Repeat similar policies for recognition and metadata queues
resource "aws_sqs_queue_policy" "recognition_queue_policy" {
  queue_url = aws_sqs_queue.recognition_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.recognition_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.image_topic.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "metadata_queue_policy" {
  queue_url = aws_sqs_queue.metadata_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.metadata_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.image_topic.arn
          }
        }
      }
    ]
  })
}

# --- Lambda Functions ---
# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3 access and SQS
resource "aws_iam_policy" "lambda_s3_sqs_policy" {
  name = "lambda_s3_sqs_policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.input_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.output_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.thumbnail_queue.arn,
          aws_sqs_queue.recognition_queue.arn,
          aws_sqs_queue.metadata_queue.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_sqs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_sqs_policy.arn
}

# Thumbnail generator Lambda function
resource "aws_lambda_function" "thumbnail_function" {
  function_name = "thumbnail-generator"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  timeout       = 300
  memory_size   = 256
  
  filename      = "lambda/thumbnail/index.zip"
  
  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}

# Connect SQS to Lambda
resource "aws_lambda_event_source_mapping" "thumbnail_trigger" {
  event_source_arn = aws_sqs_queue.thumbnail_queue.arn
  function_name    = aws_lambda_function.thumbnail_function.arn
  batch_size       = 1
}

# Image recognition Lambda function
resource "aws_lambda_function" "recognition_function" {
  function_name = "image-recognition"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  timeout       = 300
  memory_size   = 1024
  
  filename      = "lambda/recognition/function.zip"
  
  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "recognition_trigger" {
  event_source_arn = aws_sqs_queue.recognition_queue.arn
  function_name    = aws_lambda_function.recognition_function.arn
  batch_size       = 1
}

# Metadata scan Lambda function
resource "aws_lambda_function" "metadata_function" {
  function_name = "metadata-scanner"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  timeout       = 300
  memory_size   = 256
  
  filename      = "lambda/metadata/function.zip"
  
  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "metadata_trigger" {
  event_source_arn = aws_sqs_queue.metadata_queue.arn
  function_name    = aws_lambda_function.metadata_function.arn
  batch_size       = 1
}

# --- S3 Notifications ---
# Configure S3 to publish events to SNS
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  topic {
    topic_arn     = aws_sns_topic.image_topic.arn
    events        = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.image_topic_policy]
}

