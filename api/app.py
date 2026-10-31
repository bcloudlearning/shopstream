import json, os, socket
import boto3
import psycopg
from flask import Flask, jsonify, request

app = Flask(__name__)

ALLOWED_ORIGINS = {
    o.strip() for o in os.environ.get(
        "ALLOWED_ORIGINS",
        "https://shopstream.in,https://www.shopstream.in,http://172.26.77.24:5173",
    ).split(",")
}

@app.after_request
def add_cors_headers(response):
    origin = request.headers.get("Origin")
    if origin in ALLOWED_ORIGINS:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Vary"] = "Origin"
    return response

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
