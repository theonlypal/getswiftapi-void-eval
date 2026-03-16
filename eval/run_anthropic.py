import json
import os
from datetime import datetime, timezone
from pathlib import Path

from anthropic import Anthropic
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
PROMPTS = ROOT / "prompts"
RESULTS = Path(os.environ.get("GETSWIFTAPI_RESULTS_DIR", ROOT / "results"))
RUN_STAMP = os.environ.get("GETSWIFTAPI_RUN_STAMP")

load_dotenv()

MODEL = "claude-opus-4-6"
client = Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

REGIMES = [
    ("constrained", 100),
    ("unconstrained", 512),
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def stamp() -> str:
    if RUN_STAMP:
        return RUN_STAMP
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def write_outputs(prefix: str, payload: dict, text: str) -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    ts = stamp()
    (RESULTS / f"{ts}_{prefix}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (RESULTS / f"{ts}_{prefix}.txt").write_text(text, encoding="utf-8")


def run_case(name: str, prompt: str, system: str, max_tokens: int) -> None:
    response = client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": prompt}],
    )

    text_parts = []
    for block in response.content:
        if getattr(block, "type", None) == "text":
            text_parts.append(block.text)
    text = "".join(text_parts)

    payload = response.model_dump()
    write_outputs(name, payload, text)
    print(f"\n=== {name} ===\n{text}\n")


def parse_controls(raw: str) -> list[tuple[str, str]]:
    out = []
    current_name = None
    current_lines = []

    for line in raw.splitlines():
        if line.startswith("[") and line.endswith("]"):
            if current_name is not None:
                out.append((current_name, "\n".join(current_lines).strip()))
            current_name = line[1:-1]
            current_lines = []
        else:
            current_lines.append(line)

    if current_name is not None:
        out.append((current_name, "\n".join(current_lines).strip()))
    return out


def main() -> None:
    system = read_text(PROMPTS / "system.txt")
    artifact = read_text(PROMPTS / "artifact.txt")
    controls_raw = read_text(PROMPTS / "controls.txt")

    for regime_name, max_tokens in REGIMES:
        print(f"\n{'='*60}")
        print(f"REGIME: {regime_name} (max_tokens={max_tokens})")
        print(f"{'='*60}")

        run_case(f"artifact_anthropic_{regime_name}", artifact, system, max_tokens)

        for name, prompt in parse_controls(controls_raw):
            run_case(f"{name}_anthropic_{regime_name}", prompt, system, max_tokens)


if __name__ == "__main__":
    main()
