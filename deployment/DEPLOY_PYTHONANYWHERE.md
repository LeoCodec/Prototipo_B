# Despliegue del Prototipo B en PythonAnywhere

## 1. Clonar el repositorio

```bash
git clone https://github.com/LeoCodec/Prototipo_B.git
cd Prototipo_B
```

## 2. Crear virtualenv

```bash
mkvirtualenv --python=/usr/bin/python3.13 prototipo-b
workon prototipo-b
pip install -r requirements.txt
```

## 3. Comprobar OCR

```bash
which tesseract
tesseract --version
tesseract --list-langs
```

No configure `TESSERACT_CMD` hasta conocer la ruta real.

## 4. Crear Web App

En la pestaña Web:

1. Add a new web app
2. Manual configuration
3. Elegir la misma versión de Python
4. Seleccionar el virtualenv `prototipo-b`

## 5. Configurar WSGI

Copie y adapte:

`deployment/pythonanywhere_wsgi.py.template`

Cambie:

```python
PROJECT = "/home/YOURUSERNAME/Prototipo_B"
```

## 6. Static files

Si es necesario:

```text
URL: /static/
Directory: /home/YOURUSERNAME/Prototipo_B/app/static
```

## 7. Actualizar

```bash
cd ~/Prototipo_B
git pull
workon prototipo-b
pip install -r requirements.txt
```

Después pulse Reload en la pestaña Web.

## 8. Prueba del piloto

Use casos ficticios:

1. Crear caso
2. Capturar foto
3. Calidad OpenCV
4. OCR
5. Campos
6. Revisión
7. Cálculos
8. Excel
