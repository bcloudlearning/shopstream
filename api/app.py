import json, os, socket
import boto3
import psycopg
from flask import Flask, jsonify

app = Flask(__name__)

REGION = os.environ.get("AWS_REGION", "ap-south-2")
SECRET_ID = os.environ.get("DB_SECRET_ID", "shopstream/db/app")
DB_NAME = os.environ.get("DB_NAME", "shopstream")

def load_db_config():
    client = boto3.client("secretsmanager", region_name=REGION)
    secret = json.loads(client.get_secret_value(SecretId=SECRET_ID)["SecretString"])
    return {
        "host": secret["host"], "port": secret["port"],
        "user": secret["username"], "password": secret["password"],
        "dbname": DB_NAME, "sslmode": "require", "connect_timeout": 5,
    }

DB_CONFIG = load_db_config()

@app.get("/health")
def health():
    return jsonify(status="ok", host=socket.gethostname())

@app.get("/products")
def products():
    with psycopg.connect(**DB_CONFIG) as conn:
        rows = conn.execute("SELECT id, name, price FROM products ORDER BY id").fetchall()
    return jsonify([{"id": r[0], "name": r[1], "price": r[2]} for r in rows])
