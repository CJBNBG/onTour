import gzip, json

EUROPE = {"al","ad","at","ba","be","bg","by","ch","cy","cz","de","dk","ee",
          "es","fi","fr","gb","gr","hr","hu","ie","is","it","li","lt","lu",
          "lv","mc","md","me","mk","mt","nl","no","pl","pt","ro","rs","se",
          "si","sk","sm","ua","xk"}
KEEP = ["name","name:de","name:en","category","tourism","operator","ref",
        "fee","tents","caravans","nudism","internet_access","internet_access:fee",
        "sanitary_dump_station","caravan_site","caravan_site:type",
        "contact:website","contact:phone","addr:country"]
OSM = "https://www.openstreetmap.org/"

with gzip.open("all-sites-latest.json.gz", "rt", encoding="utf-8") as f:
    data = json.load(f)

out = []
for ft in data["features"]:
    p = ft["properties"]
    if p.get("addr:country", "").lower() not in EUROPE:
        continue
    lon, lat = ft["geometry"]["coordinates"]
    item = {"i": ft["id"].replace(OSM, ""), "x": round(lon, 5), "y": round(lat, 5)}
    item.update({k: p[k] for k in KEEP if k in p})
    out.append(item)

with gzip.open("europe-camping.json.gz", "wt", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
print(len(out), "Eintraege")
