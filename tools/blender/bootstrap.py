import bpy, addon_utils, json, traceback
from pathlib import Path
report={"blender":bpy.app.version_string,"addons":{}}
for name in ("blender_mcp","add_curve_sapling","ant_landscape","rigify"):
    try:
        addon_utils.enable(name, default_set=True, persistent=True)
        enabled=addon_utils.check(name)[1]
        report["addons"][name]={"enabled":enabled}
    except Exception:
        report["addons"][name]={"enabled":False,"error":traceback.format_exc()}
prefs=bpy.context.preferences.addons.get("blender_mcp")
if prefs: prefs.preferences.telemetry_consent=False
bpy.context.scene.blendermcp_auto_start_server=True
bpy.ops.wm.save_userpref()
# The dedicated portable session contains only Blender's factory scene.
for o in list(bpy.data.objects): bpy.data.objects.remove(o,do_unlink=True)
report["scene_objects"]=len(bpy.data.objects)
report_path=Path(__file__).resolve().parents[2]/"work"/"blender-mcp"/"setup-report.json"
report_path.parent.mkdir(parents=True,exist_ok=True)
report_path.write_text(json.dumps(report,indent=2))
print("BLENDER_SETUP",json.dumps(report))
