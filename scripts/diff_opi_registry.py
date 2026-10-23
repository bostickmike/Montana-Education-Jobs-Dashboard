import urllib.request
import re
import csv

url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
html = urllib.request.urlopen(req).read().decode('utf-8')

# Extract ONLY ddlDistrict select element
m_select = re.search(r'<select[^>]*name="ctl00\$ContentPlaceHolder1\$ddlDistrict"[^>]*>(.*?)</select>', html, re.DOTALL)
if not m_select:
    m_select = re.search(r'<select[^>]*id="ddlDistrict"[^>]*>(.*?)</select>', html, re.DOTALL)

select_html = m_select.group(1) if m_select else ""
options = re.findall(r'<option[^>]*>([^<]+)</option>', select_html)
districts = []
for t in options:
    t = t.strip()
    if not t or t == "- All -":
        continue
    m = re.search(r'- (\d+)$', t)
    if m:
        code = int(m.group(1))
        if code < 4000:
            name = re.sub(r'\s*-\s*\d+$', '', t).strip()
            districts.append((name, code))

print(f"Total public LEA entries in ddlDistrict (< 4000): {len(districts)}")

# Read registry
with open('k12_district_registry.csv') as f:
    reg = list(csv.DictReader(f))
reg_names = [r['District'].lower() for r in reg]

# Base names
base_dict = {}
for name, code in districts:
    base = re.sub(r'\s+(Elem|H S|K-12 Schools|K-12|Schools|High School|Elementary)$', '', name, flags=re.IGNORECASE).strip()
    if base not in base_dict:
        base_dict[base] = []
    base_dict[base].append((name, code))

unmatched = []
for base, items in sorted(base_dict.items()):
    matched = any(base.lower() in r for r in reg_names)
    if not matched:
        unmatched.append((base, items))

print(f"Total unmatched base districts: {len(unmatched)}")
for base, items in unmatched:
    codes_str = ", ".join(f"{name} ({code})" for name, code in items)
    print(f"- {base}: {codes_str}")
