#!/usr/bin/env python3
"""Record a cold Charts → Portfolio → Holdings run without clearing app data."""

import argparse
import json
import re
import subprocess
import time
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

PACKAGE = "com.codesail.market_monk"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="ADB device serial or address")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--launch-wait", type=float, default=3)
    parser.add_argument("--between-swipes", type=float, default=1)
    parser.add_argument("--flutter-profile", action="store_true")
    parser.add_argument("--swipe-ms", type=int, default=180)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    adb = ["adb", "-s", args.serial]

    def run(*command, **kwargs):
        result = subprocess.run(
            adb + list(command), check=False, capture_output=True, **kwargs
        )
        if result.returncode:
            raise RuntimeError(
                result.stdout.decode(errors="replace")
                + result.stderr.decode(errors="replace")
            )
        return result.stdout

    if args.apk:
        result = run("install", "-r", str(args.apk)).decode()
        if "Success" not in result:
            raise RuntimeError(result)
    size = run("shell", "wm", "size").decode()
    width, height = map(int, re.findall(r"(\d+)x(\d+)", size)[-1])
    run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    run("shell", "am", "force-stop", PACKAGE)
    run("shell", "input", "keyevent", "KEYCODE_HOME")
    remote = f"/data/misc/perfetto-traces/mm-swipes-{time.time_ns()}"
    video_remote = f"/sdcard/mm-swipes-{time.time_ns()}.mp4"
    config = """buffers { size_kb: 32768 fill_policy: RING_BUFFER }
 duration_ms: 20000
 data_sources { config { name: "android.surfaceflinger.frametimeline" } }
 data_sources { config { name: "linux.ftrace" ftrace_config {
   atrace_categories: "gfx" atrace_categories: "view" atrace_categories: "wm"
   atrace_apps: "com.codesail.market_monk"
   ftrace_events: "sched/sched_switch"
 } } }
"""
    trace_started = time.monotonic()
    run(
        "shell",
        "perfetto",
        "--txt",
        "-c",
        "-",
        "-o",
        remote + ".perfetto-trace",
        "--background-wait",
        input=config.encode(),
    )
    recorder = subprocess.Popen(
        adb
        + [
            "shell",
            "screenrecord",
            "--bit-rate",
            "16000000",
            "--time-limit",
            "20",
            video_remote,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    logcat = subprocess.Popen(
        adb + ["logcat", "-v", "monotonic", "-T", "1"],
        stdout=(args.output / "logcat.txt").open("wb"),
    )
    events = []

    def mark(name):
        uptime = float(run("shell", "cat", "/proc/uptime").split()[0])
        events.append({"name": name, "device_uptime_s": uptime})
        print(name, uptime, flush=True)

    try:
        time.sleep(0.5)
        mark("cold_launch")
        launch = run(
            "shell",
            "am",
            "start",
            "-W",
            "-n",
            PACKAGE + "/.MainActivity",
            "--ez",
            "trace-systrace",
            "true",
        )
        (args.output / "launch.txt").write_bytes(launch)
        vm = None
        if args.flutter_profile:
            for _ in range(50):
                log = (args.output / "logcat.txt").read_text(errors="replace")
                urls = re.findall(
                    r"Dart VM service is listening on (http://127.0.0.1:(\d+)/[^\s]+)",
                    log,
                )
                if urls:
                    url, port = urls[-1]
                    local_port = run("forward", "tcp:0", "tcp:" + port).decode().strip()
                    vm_url = url.replace(":" + port + "/", ":" + local_port + "/")
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError(
                    "Flutter VM service did not start; install a profile APK."
                )

            def rpc(method, **params):
                endpoint = vm_url + method + "?" + urllib.parse.urlencode(params)
                response = json.load(urllib.request.urlopen(endpoint, timeout=15))
                if "error" in response:
                    raise RuntimeError(response["error"])
                return response["result"]

            isolate = next(
                i["id"] for i in rpc("getVM")["isolates"] if i["name"] == "main"
            )
            rpc("setFlag", name="profiler", value="true")
            rpc("setFlag", name="profile_period", value="100")
            rpc("ext.flutter.profileWidgetBuilds", isolateId=isolate, enabled="true")
            origin = rpc("getVMTimelineMicros")["timestamp"]
            vm = (rpc, isolate, origin, local_port)
        time.sleep(args.launch_wait)
        (args.output / "charts.png").write_bytes(run("exec-out", "screencap", "-p"))
        for page in ("portfolio", "holdings"):
            mark(page + "_swipe_start")
            run(
                "shell",
                "input",
                "swipe",
                str(int(width * 0.86)),
                str(int(height * 0.52)),
                str(int(width * 0.14)),
                str(int(height * 0.52)),
                str(args.swipe_ms),
            )
            mark(page + "_swipe_end")
            time.sleep(args.between_swipes if page == "portfolio" else 3)
            (args.output / (page + ".png")).write_bytes(
                run("exec-out", "screencap", "-p")
            )
        mark("finished")
        if vm:
            rpc, isolate, origin, local_port = vm
            end = rpc("getVMTimelineMicros")["timestamp"]
            samples = rpc(
                "getCpuSamples",
                isolateId=isolate,
                timeOriginMicros=origin,
                timeExtentMicros=end - origin,
            )
            (args.output / "flutter-cpu.json").write_text(json.dumps(samples))
            functions = samples["functions"]
            ticks = Counter(
                index for sample in samples["samples"] for index in set(sample["stack"])
            )
            hotspots = []
            for index, count in ticks.most_common():
                function = functions[index]["function"]
                location = function.get("location", {})
                uri = location.get("script", {}).get("uri", "")
                if uri.startswith("package:market_monk/"):
                    hotspots.append(
                        {
                            "function": function["name"],
                            "uri": uri,
                            "line": location.get("line"),
                            "samples": count,
                        }
                    )
            (args.output / "flutter-hotspots.json").write_text(
                json.dumps(hotspots, indent=2) + "\n"
            )
            (args.output / "flutter-vm.json").write_text(json.dumps(rpc("getVM")))
            run("forward", "--remove", "tcp:" + local_port)
    finally:
        if recorder.poll() is None:
            run("shell", "pkill", "-INT", "screenrecord")
        recorder.wait(timeout=10)
        logcat.terminate()
        logcat.wait(timeout=5)
        (args.output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        run("pull", video_remote, str(args.output / "screen.mp4"))
        time.sleep(max(0, 21 - (time.monotonic() - trace_started)))
        run(
            "pull",
            remote + ".perfetto-trace",
            str(args.output / "frames.perfetto-trace"),
        )
        (args.output / "gfxinfo.txt").write_bytes(
            run("shell", "dumpsys", "gfxinfo", PACKAGE, "framestats")
        )
        run("shell", "rm", video_remote, remote + ".perfetto-trace")
    summarize(args.output)
    print("Recording saved to", args.output)


def summarize(output):
    try:
        from perfetto.trace_processor import TraceProcessor
    except ImportError:
        print("Install the Python perfetto package to generate frame summaries.")
        return
    events = json.loads((output / "events.json").read_text())
    results = {}
    with TraceProcessor(trace=str(output / "frames.perfetto-trace")) as trace:
        for page in ("portfolio", "holdings"):
            start = int(
                next(
                    event["device_uptime_s"]
                    for event in events
                    if event["name"] == page + "_swipe_start"
                )
                * 1e9
            )
            rows = trace.query(f"""
                SELECT name, COUNT(*) AS frames,
                       ROUND(MAX(dur) / 1e6, 2) AS worst_ms,
                       SUM(dur > 8333333) AS over_120hz_budget,
                       SUM(dur > 16666666) AS over_60hz_budget
                FROM slice
                WHERE ts BETWEEN {start} AND {start + 1200000000}
                  AND name IN ('Animator::BeginFrame', 'GPURasterizer::Draw')
                GROUP BY name
            """)
            results[page] = [dict(row.__dict__) for row in rows]
    (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
