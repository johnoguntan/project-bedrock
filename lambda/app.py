import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    for record in event.get('Records', []):
        key = record['s3']['object']['key']
        logger.info(f"Image received: {key}")
    
    return {
        'statusCode': 200,
        'body': 'OK'
    }
