provider "aws" {
  region = "ap-south-1"
}

# Generate a longer random suffix for uniqueness
resource "random_id" "suffix" {
  byte_length = 8
}

# Create input S3 bucket with globally unique name
resource "aws_s3_bucket" "input_images" {
  bucket        = "input-images-${random_id.suffix.hex}"
  force_destroy = true
}

# Create processed S3 bucket with globally unique name
resource "aws_s3_bucket" "processed_images" {
  bucket        = "processed-images-${random_id.suffix.hex}"
  force_destroy = true
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role_${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Inline IAM policy instead of separate aws_iam_policy resource
resource "aws_iam_role_policy" "lambda_s3_inline_policy" {
  name = "lambda_s3_inline_policy_${random_id.suffix.hex}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.input_images.arn}/*",
          "${aws_s3_bucket.processed_images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Archive the Lambda function code from the "lambda" directory
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Lambda Function Definition
resource "aws_lambda_function" "img_processor" {
  function_name = "image_processor_${random_id.suffix.hex}"
  runtime       = "python3.8"
  handler       = "lambda_function.lambda_handler"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_execution_role.arn

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.processed_images.bucket
    }
  }

  depends_on = [aws_iam_role_policy.lambda_s3_inline_policy]
}

# Allow S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.img_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_images.arn
}

# Create S3 notification to trigger Lambda on new object creation
resource "aws_s3_bucket_notification" "s3_trigger" {
  bucket = aws_s3_bucket.input_images.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.img_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Optional: Output final bucket names for reference
output "input_bucket_name" {
  value = aws_s3_bucket.input_images.bucket
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed_images.bucket
}
