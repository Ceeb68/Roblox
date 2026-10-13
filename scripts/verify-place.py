"""Check that the generated place includes the real client and server sources."""
import pathlib
import sys
import xml.etree.ElementTree as ET

path = pathlib.Path(sys.argv[1])
root = ET.parse(path).getroot()
items = list(root.iter("Item"))
scripts = {}
for item in items:
    if item.attrib.get("class") in {"Script", "LocalScript", "ModuleScript"}:
        properties = item.find("Properties")
        name = properties.find("string[@name='Name']").text
        source_element = properties.find("*[@name='Source']")
        assert source_element is not None, f"Missing script source: {name}"
        source = source_element.text or ""
        assert source.strip(), f"Empty script: {name}"
        scripts[(item.attrib["class"], name)] = source

repository = pathlib.Path(__file__).resolve().parent.parent
sources = {}
for source in (repository / "src").rglob("*.luau"):
    if source.name == "main.client.luau":
        key = ("LocalScript", "MotocrossClient")
    elif source.name.endswith(".client.luau"):
        key = ("LocalScript", "Motocross" + source.name.split(".")[0])
    elif source.name.endswith(".server.luau"):
        key = ("Script", source.name.split(".")[0])
    else:
        key = ("ModuleScript", source.stem)
    assert key not in sources, f"Ambiguous packaged script name: {key}"
    sources[key] = str(source.relative_to(repository))
missing = sources.keys() - scripts.keys()
assert not missing, f"Missing game components: {missing}"
for key, source_path in sources.items():
    assert scripts[key] == (repository / source_path).read_text(), f"Stale packaged source: {source_path}"
assert "OnServerEvent" in scripts[("Script", "main")]
assert "OnClientEvent" in scripts[("LocalScript", "MotocrossClient")]
gravity = root.find(".//Item[@class='Workspace']/Properties/*[@name='Gravity']")
assert gravity is not None and abs(float(gravity.text) - 9.81 / 0.28) < 0.0001, "Place gravity must use the simulation scale"
assert "AlignOrientation" not in scripts[("ModuleScript", "Bikes")], "Simulation must not use an upright orientation constraint"
print(f"Place verified: {len(scripts)} populated scripts, {path.stat().st_size:,} bytes.")
