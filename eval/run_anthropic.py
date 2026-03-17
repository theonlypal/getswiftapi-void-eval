import os
import sys
import time
from pathlib import Path

from anthropic import Anthropic

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from eval.common import run_eval

MODEL = "claude-opus-4-6"
client = Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
MAX_ATTEMPTS = 5
RETRYABLE_STATUS_CODES = {408, 409, 429, 500, 502, 503, 504, 529}


def is_retryable(exc: Exception) -> bool:
    status_code = getattr(exc, "status_code", None)
    if status_code in RETRYABLE_STATUS_CODES:
        return True
    return exc.__class__.__name__.lower() in {
        "internalservererror",
        "ratelimiterror",
        "apierror",
        "apiconnectionerror",
        "serviceunavailableerror",
        "overloadederror",
    }


def retry_delay(attempt: int) -> int:
    return min(2 ** (attempt - 1), 8)


def invoke(prompt: str, system: str, max_tokens: int) -> tuple[dict, str]:
    last_exc: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
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
            return response.model_dump(), text
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            if attempt == MAX_ATTEMPTS or not is_retryable(exc):
                raise
            time.sleep(retry_delay(attempt))

    raise last_exc  # pragma: no cover


def main() -> None:
    run_eval(
        provider="anthropic",
        model=MODEL,
        token_label="max_tokens",
        invoke=invoke,
    )


if __name__ == "__main__":
    main()
