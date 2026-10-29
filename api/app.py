from flask import Flask, jsonify
import socket

app = Flask(__name__)

PRODUCTS = [
    {"id": 1, "name": "Wireless Mouse", "price": 799},
    {"id": 2, "name": "USB-C Charger", "price": 1299},
    {"id": 3, "name": "Laptop Stand", "price": 1999},
]

@app.get("/health")
def health():
    return jsonify(status="ok", host=socket.gethostname())

@app.get("/products")
def products():
    return jsonify(PRODUCTS)
