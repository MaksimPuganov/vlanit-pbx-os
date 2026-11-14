#!/usr/bin/env python3
"""test_quadlet_escape.py — unit-тесты vlanit_quadlet (ponytail #25)."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "provisioning"))
import vlanit_quadlet as vq

failures = 0

def check(name, cond):
    global failures
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures += 1

# env_value: простые значения без кавычек
check("plain value unchanged", vq.env_value("admin12345") == "admin12345")
# пробелы -> кавычки
check("space quoted", vq.env_value("secret value") == '"secret value"')
# кавычки и слэши экранируются
check("quote escaped", vq.env_value('a"b') == '"a\\"b"')
# backslash без пробелов/кавычек — без изменений (экранируется только в кавычках)
check("backslash plain unchanged", vq.env_value("a\\b") == "a\\b")
check("backslash escaped in quotes",
      vq.env_value("a\\b c") == '"a\\\\b c"')

# write_env_block: вставка в [Container], идемпотентность, кавычкование
quadlet = tempfile.NamedTemporaryFile(
    "w", suffix=".container", delete=False).name
Path(quadlet).write_text("""[Unit]
Description=t

[Container]
Image=x
StopTimeout=120

[Service]
Restart=always
""")

pairs = [("PBX_NAME", "VLANit"), ("WEB_ADMIN_PASSWORD", "sec ret")]
vq.write_env_block(quadlet, pairs)
text = Path(quadlet).read_text()
check("block in Container section",
      text.index("[Container]") < text.index(vq.ENV_BEGIN)
      < text.index("[Service]"))
check("quoted password written",
      'Environment=WEB_ADMIN_PASSWORD="sec ret"' in text)
check("plain name written", "Environment=PBX_NAME=VLANit" in text)

vq.write_env_block(quadlet, pairs)
text2 = Path(quadlet).read_text()
check("idempotent rewrite", text2.count(vq.ENV_BEGIN) == 1
      and text2.count("PBX_NAME") == 1)

vq.write_env_block(quadlet, [("PBX_NAME", "New")])
text3 = Path(quadlet).read_text()
check("block replaced not duplicated", text3.count("PBX_NAME") == 1
      and "PBX_NAME=New" in text3)

Path(quadlet).unlink()
sys.exit(1 if failures else 0)
