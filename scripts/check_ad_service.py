"""Read-only verification of public ad access and draft privacy."""
import json
import os
import urllib.error
import urllib.parse
import urllib.request

base = os.environ.get('SUPABASE_URL', '').rstrip('/')
key = os.environ.get('SUPABASE_ANON_KEY', '')
if not base.startswith('https://') or not key:
    raise SystemExit('Supabase connection settings are missing.')
headers = {'apikey': key}
if not key.startswith('sb_publishable_'):
    headers['Authorization'] = 'Bearer ' + key

def get(path):
    request = urllib.request.Request(base + path, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

params = urllib.parse.urlencode({
    'select': 'id,merchant_name,title,description,sim_type,country_code,duration_days,price_krw,image_url,purchase_url,priority,updated_at',
    'country_code': 'eq.JP', 'sim_type': 'eq.esim', 'duration_days': 'eq.3',
    'order': 'priority.desc,id.desc', 'limit': '1',
})
status, body = get('/rest/v1/sim_ads?' + params)
if status != 200:
    raise SystemExit('Public ad lookup failed: HTTP ' + str(status) + ' ' + body.decode('utf-8', 'replace')[:500])
if not isinstance(json.loads(body), list):
    raise SystemExit('Public ad lookup did not return a list.')
print('Public ad lookup succeeded.')
status, body = get('/rest/v1/advertiser_drafts?select=id&limit=1')
if status not in (401, 403):
    raise SystemExit('Anonymous draft access must be denied; HTTP ' + str(status))
print('Anonymous draft access denied.')
