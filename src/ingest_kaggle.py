import os
import sys
import json
import glob
import zipfile
import boto3
from botocore.exceptions import ClientError
from awsglue.utils import getResolvedOptions

os.environ['KAGGLE_CONFIG_DIR'] = '/tmp'

def get_kaggle_credentials():
    secret_name = "ecommerce/kaggle/credentials"
    region_name = "us-east-1"

    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)

    try:
        response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        print(f"Error retrieving credentials from Secrets Manager: {e}")
        raise e

    secret_str = response['SecretString'].strip()

    try:
        secret = json.loads(secret_str)
        return secret['KAGGLE_USERNAME'], secret['KAGGLE_KEY']
    except json.JSONDecodeError:
        return "msmile1250", secret_str

args = getResolvedOptions(sys.argv, ['S3_BUCKET_NAME'])
bucket_name = args['S3_BUCKET_NAME']

os.environ['KAGGLE_USERNAME'], os.environ['KAGGLE_KEY'] = get_kaggle_credentials()

from kaggle.api.kaggle_api_extended import KaggleApi

dataset_name = 'mkechinov/ecommerce-behavior-data-from-multi-category-store'
files_to_ingest = ['2019-Oct.csv', '2019-Nov.csv']
download_path = '/tmp'

print("Initializing Kaggle API client...")
api = KaggleApi()
api.authenticate()

print(f"Downloading dataset archive {dataset_name} (compressed)...")
api.dataset_download_files(dataset_name, path=download_path, unzip=False)

zip_files = glob.glob(os.path.join(download_path, "*.zip"))
if not zip_files:
    raise FileNotFoundError("Downloaded Kaggle zip archive not found in /tmp.")

full_zip_path = zip_files[0]
print(f"Found archive: {full_zip_path}. Streaming target CSVs to S3 raw zone...")

s3_client = boto3.client('s3')

with zipfile.ZipFile(full_zip_path, 'r') as z:
    for file_name in files_to_ingest:
        print(f"Streaming {file_name} to s3://{bucket_name}/{file_name}...")
        with z.open(file_name) as file_in:
            s3_client.upload_fileobj(
                Fileobj=file_in,
                Bucket=bucket_name,
                Key=file_name
            )
        print(f"Successfully uploaded {file_name}")

print("All target CSV files successfully ingested to raw zone.")