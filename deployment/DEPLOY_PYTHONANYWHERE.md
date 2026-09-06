# Despliegue del Prototipo B en PythonAnywhere

## Clonar

```bash
git clone https://github.com/LeoCodec/Prototipo_B.git
cd Prototipo_B
```

## Virtualenv

Use la misma versión de Python que seleccione para la Web App.

```bash
mkvirtualenv --python=/usr/bin/python3.13 prototipo-b
workon prototipo-b
pip install -r requirements.txt
```

## OCR

```bash
which tesseract
tesseract --version
tesseract --list-langs
```

No copie la ruta de Windows. Use la ruta Linux real que devuelva `which tesseract`.

## Web App

1. Web
2. Add a new web app
3. Manual configuration
4. Misma versión de Python que el virtualenv
5. Configurar el virtualenv `prototipo-b`
6. Editar el archivo WSGI con `pythonanywhere_wsgi.py.template`

## Static files

Si fuera necesario:

```text
URL: /static/
Directory: /home/YOURUSERNAME/Prototipo_B/app/static
```

## Importante

No llame `app.run()` desde el archivo WSGI.

`run.py` puede contenerlo únicamente dentro de:

```python
if __name__ == "__main__":
    app.run(...)
```

## Prueba de aceptación

1. Inicio
2. Crear caso ficticio
3. Capturar una página
4. OpenCV
5. OCR
6. Extracción
7. Revisión humana
8. Cálculos
9. Excel individual
10. Excel múltiple
11. Word
12. Eliminar un caso ficticio

No utilizar expedientes reales durante la demo pública.
