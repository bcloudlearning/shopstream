INSERT INTO products (id, name, price) VALUES
    (1, 'Wireless Earbuds', 1999),
    (2, 'Smart Watch', 4999),
    (3, 'Bluetooth Speaker', 2499),
    (4, 'Laptop Stand', 1299)
ON CONFLICT (id) DO NOTHING;

SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));
