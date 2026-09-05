<p align="center">
  <img src="app/static/img/ippliap-mark.png" alt="Logo IPPLIAP" width="110">
</p>

<h1 align="center">Prototipo B — IPPLIAP</h1>

<p align="center">
  <strong>Digitalización asistida del Estudio Socioeconómico</strong><br>
  Captura móvil · OpenCV · OCR · revisión humana · análisis · Excel
</p>

<p align="center">
  Piloto experimental previo a la integración del <strong>Sistema A institucional</strong>.
</p>

1. Descripción

Prototipo B es un sistema web experimental desarrollado para el Instituto Pedagógico para Problemas del Lenguaje, I.A.P. (IPPLIAP).

Su propósito es validar, en un entorno controlado, el flujo técnico necesario para agilizar la digitalización de los datos provenientes del formato físico del estudio socioeconómico, sin eliminar la entrevista presencial ni sustituir la valoración realizada por Trabajo Social.

El formato original continúa llenándose en papel. El sistema funciona como una herramienta de apoyo para:

capturar fotografías desde celular o computadora;

evaluar la calidad de cada fotografía;

procesar imágenes con OpenCV;

aplicar OCR sobre el documento;

permitir revisión y corrección humana;

organizar datos detectados;

calcular indicadores socioeconómicos descriptivos;

generar archivos Excel para análisis y respaldo.

Principio del proyecto: la tecnología apoya el proceso, pero la decisión final permanece bajo responsabilidad humana e institucional.

2. Objetivo del Prototipo B

Validar antes del desarrollo completo del Sistema A que el flujo:

FORMATO FÍSICO
      ↓
FOTOGRAFÍA
      ↓
CONTROL DE CALIDAD
      ↓
OpenCV
      ↓
OCR
      ↓
REVISIÓN HUMANA
      ↓
DATOS E INDICADORES
      ↓
EXCEL

pueda realizarse de manera estable, comprensible y usable dentro de la institución.

3. Qué hace el sistema

Módulo

Función

Nuevo caso

Crea un expediente piloto con folio automático.

Captura

Permite tomar o seleccionar fotografías del formato físico.

Control de calidad

Evalúa enfoque e iluminación con OpenCV.

Semáforo visual

Clasifica cada fotografía como correcta, revisar o repetir.

OCR

Extrae texto preliminar de las fotografías.

Revisión humana

Permite corregir el contenido detectado antes de confirmarlo.

Extracción por campos

Organiza información como nombre, domicilio, teléfono, ingresos y gastos.

Cálculos

Genera indicadores económicos descriptivos.

Excel

Exporta los resultados del expediente y sus indicadores.

4. Qué NO hace

El Prototipo B:

no reemplaza la entrevista presencial;

no elimina el formato físico;

no determina automáticamente la cuota final;

no considera que un valor atípico signifique que una familia está mintiendo;

no asume que el OCR siempre tiene razón;

no debe utilizar expedientes reales en repositorios públicos.

La información detectada siempre debe poder ser revisada y corregida.

5. Flujo general

flowchart LR
    A[Entrevista presencial] --> B[Formato físico]
    B --> C[Fotografía desde celular]
    C --> D[Control de calidad OpenCV]
    D --> E[OCR]
    E --> F[Revisión y corrección humana]
    F --> G[Extracción por campos]
    G --> H[Cálculos descriptivos]
    H --> I[Excel]
    I --> J[Valoración institucional]

6. Arquitectura del Prototipo B

flowchart TB
    U[Usuario<br>Trabajo Social / Captura]
    W[Interfaz Web<br>Flask + Jinja2 + HTML/CSS/JS]
    S[Servicios<br>OpenCV · OCR · cálculos · Excel]
    DB[(SQLite)]
    F[Archivos<br>Fotografías]
    X[Excel]

    U --> W
    W --> S
    S --> DB
    S --> F
    S --> X

Capas principales

Usuario
  ↓
Interfaz web
  ↓
Rutas Flask
  ↓
Servicios
  ├─ procesamiento de imagen
  ├─ OCR
  ├─ extracción de campos
  ├─ cálculos
  └─ Excel
  ↓
SQLite + archivos del expediente

7. Interfaz móvil y de computadora

Celular

La interfaz móvil está orientada principalmente a la captura rápida:

colocar una hoja;

tomar fotografía;

procesar;

validar;

conservar o repetir;

continuar con la siguiente página.

El sistema puede mostrar mensajes como:

🟢 Correcta
Calidad suficiente para continuar.

🟡 Revisar
La fotografía puede utilizarse, pero conviene verificar el texto.

🔴 Repetir
La fotografía presenta problemas de enfoque o iluminación.

Computadora

La vista de escritorio permite:

revisar todas las páginas del expediente;

ampliar fotografías;

comprobar cuáles están correctas;

identificar cuáles deben repetirse;

revisar OCR;

modificar valores;

completar análisis;

generar Excel.

8. Tecnologías utilizadas

Tecnología

Uso

Python

Lenguaje principal.

Flask

Aplicación web, rutas y control del flujo.

Jinja2

Renderizado de plantillas HTML.

HTML / CSS / JavaScript

Interfaz y experiencia de usuario.

Bootstrap Icons

Iconografía de la interfaz.

SQLAlchemy

Persistencia y modelos de datos.

SQLite

Base de datos del piloto.

OpenCV

Procesamiento y control de calidad de imagen.

Tesseract OCR / pytesseract

Reconocimiento de texto.

Pillow

Apoyo para procesamiento de imágenes.

OpenPyXL

Generación de archivos Excel.

Git / GitHub

Control de versiones y respaldo de código.

9. Control de calidad de fotografías

El sistema analiza métricas de imagen antes del OCR.

Actualmente se consideran principalmente:

enfoque;

iluminación;

legibilidad general;

posibilidad de repetir una fotografía individual.

Ejemplo:

Página 1
Enfoque: 2391
Iluminación: 202
Estado: 🟢 Correcta

La clasificación es una ayuda de control de calidad; no representa una valoración socioeconómica.

10. OCR

El OCR convierte una fotografía en texto preliminar.

Ejemplo:

NOMBRE DEL NIÑO:
...

FECHA DE NACIMIENTO:
...

DOMICILIO:
...

DATOS FAMILIARES:
...

La escritura manuscrita y especialmente la cursiva pueden presentar errores, por lo que el resultado debe pasar por revisión humana.

Configuración local

El proyecto utiliza Tesseract OCR.

tesseract --version
tesseract --list-langs

Para español debe aparecer:

spa

En Windows puede ser necesario configurar:

TESSERACT_CMD=C:\Program Files\Tesseract-OCR\tesseract.exe
OCR_LANG=spa

11. Extracción y revisión de datos

El flujo previsto separa dos conceptos:

VALOR DETECTADO POR OCR
          ↓
REVISIÓN HUMANA
          ↓
VALOR CONFIRMADO

Ejemplo:

Campo

Detectado

Confirmado

Nombre

Zapata 01

Zapata 01

Código postal

55000

55000

Ingreso

13000

13000

Renta

5000

5000

La información confirmada es la que debe utilizarse para análisis posteriores.

12. Indicadores socioeconómicos

El sistema utiliza cálculos descriptivos para resumir el caso.

Ingreso total

IT = suma de ingresos

Gasto total

GT = suma de gastos

Ingreso disponible

D = IT - GT

Ingreso per cápita

IPC = IT / N

donde N representa el número de integrantes del hogar.

Disponible per cápita

DPC = (IT - GT) / N

Carga de gasto

CG = (GT / IT) × 100

Estos indicadores describen el expediente. No sustituyen la valoración de Trabajo Social ni fijan automáticamente una cuota.

13. Exportación a Excel

Uno de los objetivos principales del Prototipo B es reducir el tiempo de transcripción manual hacia Excel.

El archivo generado puede contener las siguientes hojas:

Resumen

Información principal del expediente:

folio;

identificador;

estatus;

ingreso total;

gasto total;

integrantes;

ingreso disponible;

indicadores;

cuota final autorizada.

Paginas

Control documental:

número de página;

nombre del archivo;

calidad;

nivel de enfoque;

iluminación;

errores OCR.

OCR

Contenido obtenido por reconocimiento:

página;

texto OCR;

texto confirmado.

Campos_confirmados

Comparación entre:

campo;

valor detectado;

valor confirmado;

nivel de confianza.

Indicadores

Incluye:

ingreso total;

gasto total;

disponible;

ingreso per cápita;

disponible per cápita;

carga de gasto.

El Excel puede incluir también gráficas descriptivas para facilitar la revisión del periodo.

14. Modelo de datos básico

Study
├─ id
├─ folio
├─ student_name
├─ status
├─ total_income
├─ total_expenses
├─ household_size
├─ final_fee
└─ images[]
      │
      └─ StudyImage
          ├─ page_number
          ├─ filename
          ├─ blur_score
          ├─ brightness_score
          ├─ quality_status
          ├─ ocr_text
          ├─ confirmed_text
          └─ ocr_error

15. Estructura del proyecto

Prototipo_B/
│
├── app/
│   ├── models/
│   │   └── study.py
│   │
│   ├── routes/
│   │   ├── main.py
│   │   ├── capture.py
│   │   ├── review.py
│   │   └── export.py
│   │
│   ├── services/
│   │   ├── image_service.py
│   │   ├── ocr_service.py
│   │   ├── calculations.py
│   │   └── excel_service.py
│   │
│   ├── static/
│   │   ├── css/
│   │   ├── js/
│   │   └── img/
│   │
│   └── templates/
│       ├── base.html
│       ├── index.html
│       ├── capture_mobile.html
│       ├── study_detail.html
│       └── review.html
│
├── exports/
├── instance/
├── uploads/
├── tests/
│
├── config.py
├── requirements.txt
├── run.py
├── README.md
└── .gitignore

La estructura puede crecer durante PS7–PS11 conforme se integren nuevos módulos.

16. Instalación local

Clonar

git clone https://github.com/LeoCodec/Prototipo_B.git
cd Prototipo_B

Crear entorno virtual

python -m venv venv

Activar en PowerShell

.\venv\Scripts\Activate.ps1

Instalar dependencias

pip install -r requirements.txt

Ejecutar

python run.py

Abrir:

http://127.0.0.1:5000

Si Flask se ejecuta sobre 0.0.0.0, otro dispositivo conectado a la misma red local puede acceder mediante la IP LAN mostrada en terminal.

17. Estado actual

Etapa

Estado

Diseño visual institucional

✅

Creación de expedientes

✅

Folio automático

✅

Captura desde navegador

✅

Vista móvil

✅

Guardado de fotografías

✅

OpenCV

✅

Evaluación de enfoque

✅

Evaluación de iluminación

✅

Semáforo de calidad

✅

Repetición individual

✅

Revisión en computadora

✅

Integración OCR

🟡 En pruebas

Tesseract español

🟡 Configuración

Extracción por campos

⏳ PS7

Revisión estructurada

⏳ PS8

Indicadores socioeconómicos

⏳ PS9

Excel ampliado

⏳ PS10

Despliegue piloto

⏳ PS11

18. Roadmap inmediato

PS6
OCR REAL
   ↓
PS7
EXTRACCIÓN POR CAMPOS
   ↓
PS8
REVISIÓN EDITABLE
   ↓
PS9
CÁLCULOS SOCIOECONÓMICOS
   ↓
PS10
EXCEL PROFESIONAL
   ↓
PS11
DESPLIEGUE DEL PILOTO

Una vez validado este flujo, los componentes útiles podrán integrarse al Sistema A, la plataforma institucional completa.

19. Seguridad y privacidad

Este proyecto procesa potencialmente información sensible.

Reglas del repositorio

No subir a GitHub:

.env
venv/
instance/*.db
uploads/*
exports/*
backup_*/
__pycache__/

También se deben evitar:

fotografías reales de expedientes;

nombres reales;

domicilios;

teléfonos;

ingresos;

observaciones privadas;

datos de salud.

Para demos, capturas, documentación y pruebas utilizar únicamente datos ficticios o expresamente autorizados.

20. Sistema B y Sistema A

Sistema B

Piloto experimental utilizado para comprobar:

captura;

calidad;

OCR;

extracción;

revisión;

cálculos;

Excel.

Sistema A

Plataforma institucional futura que incorporará los componentes validados del piloto e incluirá una operación más completa:

autenticación;

roles;

expedientes;

estadísticas;

configuraciones;

reportes;

administración;

seguridad;

despliegue institucional.

PROTOTIPO B
    ↓
VALIDAR
    ↓
CORREGIR
    ↓
ESTABILIZAR
    ↓
REUTILIZAR
    ↓
SISTEMA A

21. Institución

Instituto Pedagógico para Problemas del Lenguaje, I.A.P. — IPPLIAP

Este proyecto corresponde a un desarrollo de apoyo para la digitalización y análisis del proceso de estudio socioeconómico.

22. Desarrollo

Proyecto desarrollado como parte de prácticas profesionales en el área de Desarrollo y Sistemas TI.

Carrera: Ingeniería en Sistemas Computacionales
Institución académica: Universidad del Valle de México — Campus Coyoacán

<p align="center">
  <img src="app/static/img/ippliap-mark.png" alt="IPPLIAP" width="55">
</p>

