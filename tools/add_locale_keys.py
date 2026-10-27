# tools/add_locale_keys.py
# Ajoute des clés de traduction aux 11 fichiers Locale/*.lua, juste avant leur accolade finale.
# Usage, depuis la racine du dépôt : python3 tools/add_locale_keys.py cles.json
# cles.json : {"CLE": {"enUS": "...", "frFR": "...", ...}, ...}. Langue absente : texte esES pour
# esMX, sinon enUS. Refuse une clé qui existe déjà.
import json, sys, re
CODES = ["enUS","frFR","deDE","esES","esMX","itIT","ptBR","ruRU","koKR","zhCN","zhTW"]
keys = json.load(open(sys.argv[1], encoding="utf-8"))
def lua(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
for code in CODES:
    path = f"Locale/{code}.lua"
    text = open(path, encoding="utf-8").read()
    lines = []
    for key, tr in keys.items():
        if re.search(r"^\s+" + key + r" = ", text, re.M):
            sys.exit(f"{path}: {key} existe déjà")
        val = tr.get(code) or tr.get("esES" if code == "esMX" else "enUS") or tr["enUS"]
        lines.append(f"    {key} = {lua(val)},\n")
    idx = text.rstrip().rfind("}")
    text = text[:idx] + "".join(lines) + text[idx:]
    open(path, "w", encoding="utf-8").write(text)
print("ok", len(keys), "clés")
