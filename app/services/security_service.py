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
        flash("Credenciales no vÃ¡lidas.","warning")
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
