param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath
$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }
if ((git branch --show-current).Trim() -ne "main") { throw "Ejecutar en main." }

Write-Host "=== IPPLIAP PS14 - SEGURIDAD Y PRIVACIDAD ===" -ForegroundColor Green

@'
from __future__ import annotations
import os, secrets
from flask import Blueprint,redirect,render_template,request,session,url_for,flash

auth_bp=Blueprint("auth",__name__,url_prefix="/auth")

def auth_enabled(): return os.getenv("PILOT_AUTH_ENABLED","0")=="1"

@auth_bp.route("/login",methods=["GET","POST"])
def login():
    if not auth_enabled(): return redirect(url_for("main.index"))
    if request.method=="POST":
        eu=os.getenv("PILOT_USERNAME",""); ep=os.getenv("PILOT_PASSWORD","")
        su=request.form.get("username",""); sp=request.form.get("password","")
        if eu and ep and secrets.compare_digest(su,eu) and secrets.compare_digest(sp,ep):
            session.clear(); session["pilot_authenticated"]=True; return redirect(url_for("main.index"))
        flash("Credenciales no válidas.","warning")
    return render_template("login_pilot.html")

@auth_bp.post("/logout")
def logout(): session.clear(); return redirect(url_for("auth.login"))

def install_security(app):
    app.config.setdefault("MAX_CONTENT_LENGTH",12*1024*1024)
    app.config.setdefault("SESSION_COOKIE_HTTPONLY",True)
    app.config.setdefault("SESSION_COOKIE_SAMESITE","Lax")
    if os.getenv("SESSION_COOKIE_SECURE","0")=="1": app.config["SESSION_COOKIE_SECURE"]=True
    @app.before_request
    def protect():
        if not auth_enabled(): return None
        if request.endpoint in {"auth.login","diagnostics.health"} or (request.endpoint or "").startswith("static"): return None
        if not session.get("pilot_authenticated"): return redirect(url_for("auth.login"))
        return None
    @app.after_request
    def headers(response):
        response.headers.setdefault("X-Content-Type-Options","nosniff")
        response.headers.setdefault("X-Frame-Options","DENY")
        response.headers.setdefault("Referrer-Policy","no-referrer")
        response.headers.setdefault("Permissions-Policy","camera=(self), microphone=(), geolocation=()")
        if request.path.startswith(("/studies","/capture","/review","/fields","/analysis","/reports","/cases")):
            response.headers["Cache-Control"]="no-store, no-cache, must-revalidate, private"
            response.headers["Pragma"]="no-cache"; response.headers["Expires"]="0"
        if request.is_secure:
            response.headers.setdefault("Strict-Transport-Security","max-age=31536000; includeSubDomains")
        return response
'@ | Set-Content -Encoding UTF8 "app\services\security_service.py"

@'
{% extends "base.html" %}{% block title %}Acceso al piloto{% endblock %}{% block page_name %}Acceso protegido{% endblock %}{% block content %}
<section class="page-title-card" style="max-width:650px;margin:40px auto"><div><span class="eyebrow">PROTOTIPO B</span><h1>Acceso al sistema</h1><p>Use las credenciales autorizadas para la prueba institucional.</p></div></section>
<form method="POST" style="max-width:650px;margin:0 auto"><article class="review-card"><label>Usuario</label><input name="username" autocomplete="username" required><label style="margin-top:12px">Contraseña</label><input name="password" type="password" autocomplete="current-password" required><div class="bottom-actions" style="margin-top:18px"><button class="btn btn-primary" type="submit">Ingresar</button></div></article></form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\login_pilot.html"

$patch=@'
from pathlib import Path
import re
p=Path("app/__init__.py"); text=p.read_text(encoding="utf-8")
if "app.register_blueprint(auth_bp)" not in text or "install_security(app)" not in text:
    ms=list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$",text)); m=ms[-1]; ind=m.group(1); ins=""
    if "app.register_blueprint(auth_bp)" not in text: ins += f"{ind}from app.services.security_service import auth_bp, install_security\n{ind}app.register_blueprint(auth_bp)\n"
    elif "install_security" not in text: ins += f"{ind}from app.services.security_service import install_security\n"
    if "install_security(app)" not in text: ins += f"{ind}install_security(app)\n"
    text=text[:m.start()]+ins+"\n"+text[m.start():]; p.write_text(text,encoding="utf-8")
'@
$tmp=Join-Path $env:TEMP "ps14_patch.py"; $patch|Set-Content -Encoding UTF8 $tmp; & $Py $tmp; Remove-Item $tmp -Force

$e=".env.example"; if (-not (Test-Path $e)) { New-Item -ItemType File $e | Out-Null }
$current=Get-Content $e -Raw
foreach($entry in @("PILOT_AUTH_ENABLED=0","PILOT_USERNAME=","PILOT_PASSWORD=","SESSION_COOKIE_SECURE=0")){
  $key=($entry -split "=")[0]; if($current -notmatch "(?m)^$([regex]::Escape($key))="){ Add-Content $e "`n$entry" }
}

& $Py -m compileall app -q
& $Py -c "from app import create_app; a=create_app(); c=a.test_client(); r=c.get('/diagnostics/health'); print(r.status_code,r.get_json())"
Write-Host "PS14 listo. Local deja PILOT_AUTH_ENABLED=0. En nube con datos reales: auth + HTTPS obligatorios." -ForegroundColor Green
