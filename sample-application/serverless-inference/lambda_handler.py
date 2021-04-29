import json
import os
import base64
import sys

sys.path.append("/mnt/access")
import numpy as np
from PIL import Image
from tensorflow.keras.preprocessing.image import load_img, img_to_array
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input
from tensorflow.keras.models import load_model

model = load_model("/mnt/access/mobilenetv2")

def base64_to_input(img):
    img = base64.b64decode(img)
    with open(f'/tmp/temp.jpeg', 'wb') as file:
        file.write(img)
    img = load_img(f'/tmp/temp.jpeg', target_size=(224, 224))
    img = img_to_array(img)
    img = img.reshape((1, img.shape[0], img.shape[1], img.shape[2]))
    img = preprocess_input(img)
    return img

def decode_predictions(preds, top=5):
    with open('/mnt/access/imagenet_class_index.json') as f:
        CLASS_INDEX = json.load(f)
    results = []
    for pred in preds:
        top_indices = pred.argsort()[-top:][::-1]
        result = [tuple(CLASS_INDEX[str(i)]) + (pred[i],) for i in top_indices]
        result.sort(key=lambda x: x[2], reverse=True)
        results.append(result)
    return results

def inference_model(img):
    result = model.predict(img)
    result = decode_predictions(result)[0]
    result = [(img_class, label, str(round(acc * 100, 4)) + '%') for img_class, label, acc in result]
    return result
    
def lambda_handler(event, context):
    
    img = event['content']
    img = base64_to_input(img)
    result = inference_model(img)
    print(result)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
