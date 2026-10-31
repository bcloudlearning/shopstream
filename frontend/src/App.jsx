import { useEffect, useState } from "react";

const API = "https://api.shopstream.in";

export default function App() {
  const [products, setProducts] = useState([]);
  const [error, setError] = useState("");

  useEffect(() => {
    fetch(`${API}/products`)
      .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
      .then(setProducts)
      .catch((e) => setError(e.message));
  }, []);

  return (
    <main style={{ fontFamily: "system-ui", maxWidth: 640, margin: "40px auto", padding: 16 }}>
      <h1>ShopStream</h1>
      {error && <p>Could not load products: {error}</p>}
      <ul>
        {products.map((p) => <li key={p.id}>{p.name} — ₹{p.price}</li>)}
      </ul>
    </main>
  );
}
