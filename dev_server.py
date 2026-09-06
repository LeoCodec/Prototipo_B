from __future__ import annotations
import os
from app import create_app
app=create_app(); app.config["TEMPLATES_AUTO_RELOAD"]=True; app.jinja_env.auto_reload=True
if __name__=="__main__":
    app.run(host=os.getenv("DEV_HOST","127.0.0.1"),port=int(os.getenv("DEV_PORT","5000")),debug=False,use_reloader=True,use_debugger=False)
