"""Read database credentials from AWS Secrets Manager.

Passwords never appear in code, in Terraform output, or in environment variables.
Each Lambda reads the secret once when it starts, then reuses it.
"""

import json
from functools import cache

import boto3

from app import config


@cache
def read_secret(secret_arn):
    """Return a secret's JSON value as a dictionary.

    For example: {"username": ..., "password": ...}
    """
    client = boto3.client("secretsmanager", region_name=config.AWS_REGION)
    response = client.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])
