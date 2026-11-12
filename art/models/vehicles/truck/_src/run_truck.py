# The background-Blender entry for the crew's truck, the beacon and the exit marker (METRO 9 M9):
#   blender -b --factory-startup --python run_truck.py -- [all|build]
# Builds every piece into the "truck" scene and (all) exports one .glb per piece, the manifest
# (truck.json, Godot space: tris, bounds, collision boxes, named points) and the .blend; prints one JSON
# line "TRK_RESULT {...}". Set TEMP / TMP to E: before running (C: is full).
import json, os, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
step = argv[0] if argv else "all"
HERE = os.path.dirname(os.path.abspath(__file__))
g = {"__name__": "truck_kit", "__file__": os.path.join(HERE, "truck_header.py")}
for part in ("truck_header.py", "truck_build.py", "truck_body.py"):
	path = os.path.join(HERE, part)
	exec(compile(open(path, encoding="utf-8").read(), path, "exec"), g)
res = g["build"]()
if step == "all":
	res["export"] = g["export"]()
print("TRK_RESULT " + json.dumps(res))
