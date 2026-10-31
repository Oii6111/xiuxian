"""Package the current PR4 combat/lifecycle delivery without local caches or saves."""
from pathlib import Path
import hashlib, json, re, subprocess, zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"outputs"/"combat-lifecycle"
LOG=ROOT/"work"/"action-assets"/"verified-validation.log"
text=LOG.read_text(encoding="utf-8-sig")
if "PR4 and A integration checks passed." not in text or re.search(r"SCRIPT ERROR:|^ERROR:|FAIL:",text,re.M):
    raise SystemExit("Final PR4 validation is incomplete or contains errors.")
markers=[]
for line in text.splitlines():
    m=re.search(r"([A-Z0-9_]+): (\d+) assertions; (\d+) failures",line)
    if m:
        markers.append({"suite":m[1],"checks":int(m[2]),"failures":int(m[3])})
        continue
    m=re.search(r"([A-Z0-9_]+) (\d+) assertions; (\d+) failures",line)
    if m:
        markers.append({"suite":m[1],"checks":int(m[2]),"failures":int(m[3])})
        continue
    m=re.search(r"([A-Z /_]+) RESULT: PASS \((\d+) passed, (\d+) failures\)",line)
    if m:
        markers.append({"suite":m[1].strip(),"checks":int(m[2]),"failures":int(m[3])})
        continue
    m=re.search(r"([A-Z ]+ TESTS): (\d+) passed, (\d+) failed",line)
    if m:
        markers.append({"suite":m[1].strip(),"checks":int(m[2]),"failures":int(m[3])})
unique={row["suite"]:row for row in markers}
if len(unique)<35 or any(row["failures"] for row in unique.values()):
    raise SystemExit(f"Expected the complete PR4 validation set, got {len(unique)} suites.")
contract_path=ROOT/"data/combat/a_delivery_sources.json"
contract=json.loads(contract_path.read_text(encoding="utf-8"))
paths=set(contract["files"])
paths.add("data/combat/a_delivery_sources.json")
if any("arena" in name.lower() and "combat" in name.lower() for name in paths):
    raise SystemExit("Delivery list contains excluded arena files.")
for name in sorted(paths):
    if not (ROOT/name).is_file(): raise SystemExit("Missing delivery source: "+name)
base=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip()
assets=json.loads((ROOT/"data/combat/action_atlases.json").read_text(encoding="utf-8"))["assets"]
if len(assets)!=24 or sum(row["frame_count"] for row in assets.values())!=384:
    raise SystemExit("Animation manifest is incomplete.")
report={"date":"2026-10-31","base":base,"branch":"feat/a-combat-lifecycle","source_pr":"https://github.com/Oii6111/xiuxian/pull/4","engine":"Godot 4.7.2 Compatibility","status":"PR4 fixed progression, combat lifecycle and generated action assets validated","suite_count":len(unique),"total_checks":sum(row["checks"] for row in unique.values()),"failures":0,"animations":{"atlases":24,"redrawn_frames":384,"bosses":20,"hero_avatars":2,"vfx_families":8,"tool":"built-in imagegen"},"limitations":["Deterministic drivers are engineering regression checks, not human balance data","Main clips use four keyframes and can receive additional in-betweens later","Authoritative remote settlement and multiplayer services remain integration work","No remote upload performed"]}
OUT.mkdir(parents=True,exist_ok=True)
(OUT/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
manifest=[]
with zipfile.ZipFile(OUT/"a-combat-lifecycle-source.zip","w",zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(paths):
        path=ROOT/name;raw=path.read_bytes()
        manifest.append({"path":name,"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest()})
        archive.write(path,name)
(OUT/"source-manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
with zipfile.ZipFile(OUT/"a-combat-lifecycle-source.zip") as archive:
    if len(archive.namelist())!=len(manifest): raise SystemExit("Archive manifest length mismatch.")
    for row in manifest:
        if hashlib.sha256(archive.read(row["path"])).hexdigest()!=row["sha256"]: raise SystemExit("Archive hash mismatch: "+row["path"])
(OUT/"animated-combat"/"validation.log").write_text(text,encoding="utf-8")
print(f"Packaged {len(manifest)} combat/lifecycle source files; {len(unique)} suites / {report['total_checks']} checks / zero failures.")
