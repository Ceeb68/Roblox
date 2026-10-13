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

expected = {
    ("Script", "main"),
    ("LocalScript", "MotocrossClient"),
    ("ModuleScript", "Bikes"),
    ("ModuleScript", "Track"),
    ("ModuleScript", "Config"),
    ("ModuleScript", "RaceRules"),
}
missing = expected - scripts.keys()
assert not missing, f"Missing game components: {missing}"
sources = {
    ("Script", "main"): "src/server/main.server.luau",
    ("LocalScript", "MotocrossClient"): "src/client/main.client.luau",
    ("ModuleScript", "Bikes"): "src/server/Bikes.luau",
    ("ModuleScript", "Track"): "src/server/Track.luau",
    ("ModuleScript", "Config"): "src/shared/Config.luau",
    ("ModuleScript", "RaceRules"): "src/shared/RaceRules.luau",
}
repository = pathlib.Path(__file__).resolve().parent.parent
for key, source_path in sources.items():
    assert scripts[key] == (repository / source_path).read_text(), f"Stale packaged source: {source_path}"
assert "OnServerEvent" in scripts[("Script", "main")]
assert "OnClientEvent" in scripts[("LocalScript", "MotocrossClient")]
print(f"Place verified: {len(scripts)} populated scripts, {path.stat().st_size:,} bytes.")
