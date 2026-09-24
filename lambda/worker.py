import concurrent.futures
import json
import os
import random
import time
import urllib.error
import urllib.request
from collections import Counter

import boto3


S3 = boto3.client("s3")
SECRETS = boto3.client("secretsmanager")
LATENCY_BUCKETS_MS = (10, 25, 50, 100, 250, 500, 1000, 2500, 5000)


def _required(event, name):
    value = event.get(name)
    if value is None or value == "":
        raise ValueError(f"Missing required field: {name}")
    return value


def _target_url(target):
    names = {
        "spring": "SPRING_TARGET_URL",
        "java": "JAVA_TARGET_URL",
        "collector": "COLLECTOR_URL",
    }
    if target not in names:
        raise ValueError("target must be spring, java, or collector")
    return os.environ[names[target]].rstrip("/")


def _collector_key():
    response = SECRETS.get_secret_value(SecretId=os.environ["COLLECTOR_SECRET_ARN"])
    return json.loads(response["SecretString"])["apiKey"]


def _choose_request(requests):
    weights = [int(item.get("weight", 1)) for item in requests]
    return random.choices(requests, weights=weights, k=1)[0]


def _latency_bucket(elapsed_ms):
    for upper in LATENCY_BUCKETS_MS:
        if elapsed_ms < upper:
            return f"lt_{upper}ms"
    return "gte_5000ms"


def _run_lane(base_url, requests, headers, deadline, request_interval_ms):
    result = {
        "requests": 0,
        "successes": 0,
        "failures": 0,
        "timeouts": 0,
        "latencyTotalMs": 0.0,
        "latencyMaxMs": 0.0,
        "histogram": Counter(),
        "statuses": Counter(),
        "errors": Counter(),
    }

    while time.monotonic() < deadline:
        specification = _choose_request(requests)
        method = specification.get("method", "GET").upper()
        body = specification.get("body")
        encoded = None if body is None else json.dumps(body).encode("utf-8")
        request_headers = dict(headers)
        if encoded is not None:
            request_headers.setdefault("Content-Type", "application/json")

        request = urllib.request.Request(
            base_url + specification["path"],
            data=encoded,
            headers=request_headers,
            method=method,
        )
        started = time.perf_counter()
        result["requests"] += 1
        try:
            with urllib.request.urlopen(request, timeout=float(specification.get("timeoutSeconds", 10))) as response:
                response.read()
                status = response.status
                result["statuses"][str(status)] += 1
                if 200 <= status < 400:
                    result["successes"] += 1
                else:
                    result["failures"] += 1
        except urllib.error.HTTPError as error:
            result["statuses"][str(error.code)] += 1
            result["failures"] += 1
        except TimeoutError:
            result["timeouts"] += 1
            result["failures"] += 1
        except Exception as error:  # Result aggregation must survive individual request failures.
            result["errors"][type(error).__name__] += 1
            result["failures"] += 1
        finally:
            elapsed_ms = (time.perf_counter() - started) * 1000
            result["latencyTotalMs"] += elapsed_ms
            result["latencyMaxMs"] = max(result["latencyMaxMs"], elapsed_ms)
            result["histogram"][_latency_bucket(elapsed_ms)] += 1

        # Limit each lane to at most one request start per configured interval.
        # The response time is included in the interval, so a slow response does
        # not add an unnecessary extra delay or create a catch-up burst.
        remaining_interval_seconds = (request_interval_ms - elapsed_ms) / 1000
        remaining_test_seconds = deadline - time.monotonic()
        if remaining_interval_seconds > 0 and remaining_test_seconds > 0:
            time.sleep(min(remaining_interval_seconds, remaining_test_seconds))

    return result


def _merge(parts):
    merged = {
        "requests": 0,
        "successes": 0,
        "failures": 0,
        "timeouts": 0,
        "latencyTotalMs": 0.0,
        "latencyMaxMs": 0.0,
        "histogram": Counter(),
        "statuses": Counter(),
        "errors": Counter(),
    }
    for part in parts:
        for field in ("requests", "successes", "failures", "timeouts", "latencyTotalMs"):
            merged[field] += part[field]
        merged["latencyMaxMs"] = max(merged["latencyMaxMs"], part["latencyMaxMs"])
        for field in ("histogram", "statuses", "errors"):
            merged[field].update(part[field])
    for field in ("histogram", "statuses", "errors"):
        merged[field] = dict(merged[field])
    merged["latencyAverageMs"] = (
        merged["latencyTotalMs"] / merged["requests"] if merged["requests"] else 0
    )
    return merged


def handler(event, _context):
    run_id = str(_required(event, "runId"))
    worker_id = int(_required(event, "workerId"))
    target = str(_required(event, "target"))
    concurrency = int(event.get("concurrency", 1))
    duration_seconds = int(event.get("durationSeconds", 60))
    request_interval_ms = int(event.get("requestIntervalMs", 0))
    start_at_ms = int(event.get("startAtEpochMs", int(time.time() * 1000)))
    requests = event.get("requests") or [{
        "method": event.get("method", "GET"),
        "path": _required(event, "path"),
        "body": event.get("body"),
    }]

    if not 1 <= concurrency <= 100:
        raise ValueError("concurrency must be between 1 and 100")
    if not 1 <= duration_seconds <= 840:
        raise ValueError("durationSeconds must be between 1 and 840")
    if not 0 <= request_interval_ms <= 60_000:
        raise ValueError("requestIntervalMs must be between 0 and 60000")

    wait_seconds = (start_at_ms - int(time.time() * 1000)) / 1000
    if wait_seconds > 15:
        raise ValueError("startAtEpochMs must be no more than 15 seconds in the future")
    if wait_seconds > 0:
        time.sleep(wait_seconds)

    headers = {str(key): str(value) for key, value in event.get("headers", {}).items()}
    headers["X-Load-Test-Run-ID"] = run_id
    headers["X-Load-Test-Worker-ID"] = str(worker_id)
    if target == "collector":
        headers["Authorization"] = f"Bearer {_collector_key()}"

    started_at = time.time()
    deadline = time.monotonic() + duration_seconds
    base_url = _target_url(target)
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(
                _run_lane,
                base_url,
                requests,
                headers,
                deadline,
                request_interval_ms,
            )
            for _ in range(concurrency)
        ]
        merged = _merge([future.result() for future in futures])

    result = {
        "runId": run_id,
        "workerId": worker_id,
        "target": target,
        "concurrency": concurrency,
        "durationSeconds": duration_seconds,
        "requestIntervalMs": request_interval_ms,
        "startedAtEpochMs": int(started_at * 1000),
        "finishedAtEpochMs": int(time.time() * 1000),
        **merged,
    }
    key = f"runs/{run_id}/worker-{worker_id:04d}.json"
    S3.put_object(
        Bucket=os.environ["RESULT_BUCKET"],
        Key=key,
        Body=json.dumps(result, separators=(",", ":")).encode("utf-8"),
        ContentType="application/json",
    )
    return {"resultKey": key, **result}
