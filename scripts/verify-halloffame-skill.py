#!/usr/bin/env python3

from pathlib import Path
import sys


REQUIRED_ENV_VARS = (
    "HOF_API_URL",
    "HOF_AGENT_PROVIDER",
    "HOF_AGENT_ID",
    "HOF_USERNAME",
    "HOF_FIRSTNAME",
    "HOF_LASTNAME",
    "HOF_EMAIL",
    "HOF_PASSWORD",
)


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail("Usage: verify-halloffame-skill.py /path/to/SKILL.md")

path = Path(sys.argv[1])

if not path.is_file():
    fail(f"Missing Hall Of Fame SKILL.md: {path}")

text = path.read_text()

if "'requires':" not in text:
    fail("Hall Of Fame skill is missing metadata.openclaw.requires")

if "'envVars':" not in text:
    fail("Hall Of Fame skill is missing metadata.openclaw.envVars")

requires = text.split("'requires':", 1)[1].split("'envVars':", 1)[0]

if "'env':" in requires:
    fail("Hall Of Fame must not use requires.env load-time gating")

for name in REQUIRED_ENV_VARS:
    declaration = f"'name': '{name}'"
    if declaration not in text:
        fail(f"Missing transparent envVars declaration: {name}")


if "user-invocable: true" not in text:
    fail("Hall Of Fame must remain user-invocable")

if "disable-model-invocation: false" not in text:
    fail("Hall Of Fame must remain visible to the OpenClaw model for slash-command dispatch")

if "## Activation boundary" not in text:
    fail("Hall Of Fame skill is missing the explicit activation boundary")

if "## OpenClaw invocation compatibility" not in text:
    fail("Hall Of Fame skill is missing the OpenClaw invocation compatibility section")

if "active agent workspace's `.env`" not in text:
    fail("Hall Of Fame skill must disclose its workspace .env credential loader")

if "does not execute or source" not in text:
    fail("Hall Of Fame skill must disclose that workspace .env is parsed, not executed")

if "## Environment access" not in text:
    fail("Hall Of Fame skill is missing the Environment access transparency section")

print("Hall Of Fame environment contract verified.")
