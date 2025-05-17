import boto3
import os
import io
from PIL import Image

s3 = boto3.client('s3')
output_bucket = os.environ['OUTPUT_BUCKET']

def lambda_handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    # Download image from S3
    response = s3.get_object(Bucket=bucket, Key=key)
    image_data = response['Body'].read()

    # Process image (e.g., resize)
    img = Image.open(io.BytesIO(image_data))
    img = img.resize((128, 128))  # Resize to 128x128

    # Save resized image to memory
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG")
    buffer.seek(0)

    # Upload to output S3 bucket
    s3.put_object(Bucket=output_bucket, Key=key, Body=buffer, ContentType='image/jpeg')

    return {
        'statusCode': 200,
        'body': 'Image processed successfully!'
    }

