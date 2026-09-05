import cv2
import numpy as np


def analyze_quality(path):
    img = cv2.imread(str(path))
    if img is None:
        return {"blur": 0, "brightness": 0, "status": "ERROR"}

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    brightness = float(np.mean(gray))

    if blur < 55:
        status = "ROJO"
    elif brightness < 55 or brightness > 220 or blur < 100:
        status = "AMARILLO"
    else:
        status = "VERDE"

    return {"blur": round(blur, 2), "brightness": round(brightness, 2), "status": status}


def preprocess_for_ocr(path):
    img = cv2.imread(str(path))
    if img is None:
        return None
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    return cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                 cv2.THRESH_BINARY, 31, 12)
