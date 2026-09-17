import argparse
import concurrent.futures
import json
import time
import uuid
from pathlib import Path

import boto3
from botocore.config import Config


def invoke(client, function_name, payload):
    response = client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode("utf-8"),
    )
    body = json.loads(response["Payload"].read())
    if response.get("FunctionError"):
        raise RuntimeError(body)
    return body


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--function-name", required=True)
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--region", default="ap-northeast-2")
    args = parser.parse_args()

    scenario = json.loads(Path(args.scenario).read_text(encoding="utf-8"))
    run_id = scenario.get("runId") or f"{scenario['target']}-{uuid.uuid4()}"
    start_at_ms = int((time.time() + 10) * 1000)
    client = boto3.client(
        "lambda",
        region_name=args.region,
        config=Config(read_timeout=900, connect_timeout=10, retries={"max_attempts": 2}),
    )

    payloads = []
    for worker_id in range(args.workers):
        payload = dict(scenario)
        payload.update({"runId": run_id, "workerId": worker_id, "startAtEpochMs": start_at_ms})
        payloads.append(payload)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        results = list(executor.map(lambda payload: invoke(client, args.function_name, payload), payloads))

    total_requests = sum(item["requests"] for item in results)
    total_successes = sum(item["successes"] for item in results)
    total_failures = sum(item["failures"] for item in results)
    output = {
        "runId": run_id,
        "workers": args.workers,
        "requests": total_requests,
        "successes": total_successes,
        "failures": total_failures,
        "resultKeys": [item["resultKey"] for item in results],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

