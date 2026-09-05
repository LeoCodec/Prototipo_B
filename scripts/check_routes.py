from app import create_app

app = create_app()

print("\n=== RUTAS FLASK REGISTRADAS ===\n")

for rule in sorted(app.url_map.iter_rules(), key=lambda x: str(x)):
    methods = ",".join(sorted(m for m in rule.methods if m not in {"HEAD", "OPTIONS"}))
    print(f"{methods:12} {rule}")

print("\nRutas esperadas del Prototipo B:")
print("POST /studies/new")
print("GET  /studies/<id>")
print("GET/POST /capture/<id>/mobile")
print("POST /capture/<id>/delete/<image_id>")
print("GET/POST /review/<id>")
print("GET /export/<id>/excel")
