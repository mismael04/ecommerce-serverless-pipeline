import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
sfn_client = boto3.client('stepfunctions')

STATE_MACHINE_ARN = os.environ.get('STATE_MACHINE_ARN')

def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))
    
    # Extract bucket and object key from the event payload
    detail = event.get('detail', event)
    bucket = detail.get('bucket', {}).get('name') or detail.get('bucket_name')
    key = detail.get('object', {}).get('key') or detail.get('object_key')
    
    if not bucket or not key:
        raise ValueError("Missing required S3 bucket or object key in event payload.")
        
    logger.info(f"Validating file schema for s3://{bucket}/{key}")
    
    try:
        # Read the first chunk (headers) of the CSV file
        response = s3_client.get_object(Bucket=bucket, Key=key, Range='bytes=0-512')
        content = response['Body'].read().decode('utf-8')
        lines = content.splitlines()
        
        if not lines:
            raise ValueError("Uploaded file is empty.")
            
        # Extract header and normalize to lowercase for case-insensitive comparison
        header = lines[0].lower()
        logger.info(f"Extracted header: {header}")
        
        # Enforce ONLY quantity and customerid
        required_columns = ["quantity", "customerid"]
        missing_columns = [col for col in required_columns if col not in header]
        
        if missing_columns:
            raise ValueError(f"Schema Validation Error: Missing required column(s): {missing_columns}")
            
        logger.info("Schema validation passed successfully. Triggering Step Functions...")
        
        # Trigger Step Functions only when validation succeeds
        response = sfn_client.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps({"bucket_name": bucket, "object_key": key})
        )
        
        return {
            "statusCode": 200,
            "status": "VALID_AND_TRIGGERED",
            "executionArn": response['executionArn']
        }
        
    except Exception as e:
        logger.error(f"Data validation failed: {str(e)}")
        raise e