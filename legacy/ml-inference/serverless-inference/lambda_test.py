import json
import os
import base64
import sys
from io import BytesIO

sys.path.append("/mnt/efs/packages")
import numpy as np
from PIL import Image
from requests_toolbelt.multipart import decoder

from tensorflow.keras.applications.mobilenet_v2 import preprocess_input
from tensorflow.keras.models import load_model

model = load_model("/mnt/efs/packages/mobilenetv2")

efs_package_list = os.listdir("/mnt/efs/packages")

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps(f"{efs_package_list}")
    }
