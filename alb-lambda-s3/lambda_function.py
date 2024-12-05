"""Return S3 bucket content"""
# pylint:disable=broad-exception-caught
import os

import boto3

s3 = boto3.client("s3")


def lambda_handler(event, _):
    """Default entry point"""
    try:
        # Get the bucket name from environment variable
        bucket_name = os.environ["S3_BUCKET"]

        # Extract object key from the event
        object_key = os.path.normpath(event["path"].strip("/"))
        if object_key == ".":
            object_key = "index.html"

        # Get the object from S3
        response = s3.get_object(Bucket=bucket_name, Key=object_key)

        # Read the content of the object
        content = response["Body"].read().decode("utf-8")
        mime_type = response["ContentType"]

        return {
            "statusCode": 200,
            "body": content,
            "headers": {"Content-Type": mime_type},
        }
    except Exception:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "text/html"},
            "body": """
<!DOCTYPE html>
<html>
<head>
    <title>404 Not Found</title>
</head>
<body>
    <h1>404 Not Found</h1>
    <p>The requested URL was not found on this server.</p>
</body>
</html>
""",
        }
