import json,sys,urllib.request
B,ID,U,P=sys.argv[1:5]
def call(m,path,tok=None,body=None):
    r=urllib.request.Request(B+path,method=m,data=None if body is None else json.dumps(body).encode(),headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})})
    try:
        x=urllib.request.urlopen(r,timeout=60);raw=x.read();return x.status,(json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read() or b'null')
_,t=call("POST","/auth/login",body={"username":U,"password":P});tok=t["access_token"]
_,b=call("GET",f"/backups/{ID}",tok);print("status",b["status"],"| zin:",b["restore_confirmation"][:40],"...")
s,r=call("POST",f"/backups/{ID}/restore",tok,{"confirm":b["restore_confirmation"]});print("restore ->",s,json.dumps(r)[:260])
