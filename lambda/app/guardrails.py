"""Amazon Bedrock Guardrails: check the question before answering, and the answer before sending it.

The guardrail (created by Terraform in bedrock.tf) blocks harmful content and
prompt-injection attempts. We call it with the ApplyGuardrail API, separately
from the model, so the same checks work whatever model writes the answer.

Until the guardrail exists GUARDRAIL_ID is empty and the checks are skipped,
so the assistant still answers while you are part way through building the stack.
"""

from functools import cache

from app import config


@cache
def bedrock():
    import boto3

    return boto3.client("bedrock-runtime", region_name=config.AWS_REGION)


def check(text, source):
    """Check one piece of text.

    source  "INPUT" for the employee's question, "OUTPUT" for the answer.

    Returns (intervened, text_to_use). When the guardrail intervenes, text_to_use
    is its replacement: a blocked-content message, or the text with parts masked.
    """
    if not config.GUARDRAIL_ID:
        return False, text

    response = bedrock().apply_guardrail(
        guardrailIdentifier=config.GUARDRAIL_ID,
        guardrailVersion=config.GUARDRAIL_VERSION,
        source=source,
        content=[{"text": {"text": text}}],
    )

    if response["action"] != "GUARDRAIL_INTERVENED":
        return False, text

    replacement = " ".join(output["text"] for output in response.get("outputs", []))
    return True, replacement or "Sorry, I can't help with that request."
