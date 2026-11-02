#!/usr/bin/env python3
"""seed | snap against a Pleya Server. Usage: pwstate.py BASE_URL seed|snap  (accounts are the fictional test ones)."""
import json, sys, urllib.request, uuid, datetime
BASE = sys.argv[1].rstrip('/') + '/pleya/v1'
ACC = {'probe': 'een-lang-genoeg-wachtwoord', 'tweedeadmin': 'een-lang-genoeg-wachtwoord-b'}
def call(method, path, token=None, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read(); return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]
def login(u, p):
    s, d = call('POST', '/auth/login', body={'username': u, 'password': p}); assert s == 200, (u, s, d); return d['access_token']
def movies(t):
    _, libs = call('GET', '/libraries', t); lid = [l['id'] for l in libs['items'] if l['kind'] == 'movies'][0]
    _, d = call('GET', f'/libraries/{lid}/items?limit=50', t); return {i['title']: i['id'] for i in d['items']}
def watch(t, item, done):
    return call('POST', '/watch-state', t, {'item_id': item, 'session_id': str(uuid.uuid4()), 'position_ms': 2000 if done else 0, 'duration_ms': 2000,
        'occurred_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'completed': done, 'explicit_action': 'mark_watched' if done else 'mark_unwatched'})[0]
if sys.argv[2] == 'seed':
    ta, tb = login('probe', ACC['probe']), login('tweedeadmin', ACC['tweedeadmin']); m = movies(ta)
    print('A fav', call('PUT', f"/favorites/{m['Blade Runner']}", ta)[0], 'A rate', call('PUT', f"/ratings/{m['Grease']}", ta, {'rating': 9})[0], 'A watched', watch(ta, m['Blade Runner'], True))
    print('B fav', call('PUT', f"/favorites/{m['Grease']}", tb)[0], 'B rate', call('PUT', f"/ratings/{m['Blade Runner']}", tb, {'rating': 3})[0])
    print('settings', call('PATCH', '/settings', ta, {'server_name': 'Pleya Windows Test'})[0])
else:
    out = {}
    for u, p in ACC.items():
        t = login(u, p); m = movies(t); _, fav = call('GET', '/favorites?limit=50', t)
        out[u] = {'favorites': sorted(i['title'] for i in fav['items'])}
        for title, iid in sorted(m.items()):
            _, it = call('GET', f'/items/{iid}', t); out[u][title] = {'rating': it.get('rating'), 'watched': (it.get('user_state') or {}).get('watched')}
    ta = login('probe', ACC['probe']); _, users = call('GET', '/users', ta); _, st = call('GET', '/settings', ta)
    out['users'] = sorted((x['username'], x['role']) for x in users['items']); out['server_name'] = st.get('server_name')
    print(json.dumps(out, indent=1, sort_keys=True))
