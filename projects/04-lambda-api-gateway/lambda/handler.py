import json
import os

ITEMS = [
    {"id": 1, "name": "EC2 Instance", "type": "compute"},
    {"id": 2, "name": "S3 Bucket", "type": "storage"},
    {"id": 3, "name": "RDS Database", "type": "database"},
]


def lambda_handler(event, context):
    method = event.get("httpMethod", "GET")

    if method == "GET":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "items": ITEMS,
                "count": len(ITEMS),
                "stage": os.environ.get("STAGE", "unknown")
            })
        }
    elif method == "POST":
        body = json.loads(event.get("body") or "{}")
        new_item = {
            "id": len(ITEMS) + 1,
            "name": body.get("name", "Unnamed"),
            "type": body.get("type", "unknown")
        }
        ITEMS.append(new_item)
        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"created": new_item, "total": len(ITEMS)})
        }
    else:
        return {
            "statusCode": 405,
            "body": json.dumps({"error": "Method not allowed"})
        }
