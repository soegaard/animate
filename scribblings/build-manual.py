#!/usr/bin/env python3
"""Check examples, generate required figures, and build the five-part manual.

Run explicitly; stored frame strips do not launch animation renderers.
Ordinary Scribble builds may evaluate small native Pict examples.
Every subprocess has separate stdout/stderr logs. A failed stage stops the run.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time


def run_stage(name, command, root, logs, report):
    """Tee both streams without a PIPE deadlock; preserve the actual exit code."""
    item = {"name": name, "command": [str(x) for x in command], "status": "running"}
    report["stages"].append(item)
    out_path, err_path = logs/(name+".stdout.txt"), logs/(name+".stderr.txt")
    item.update(stdout=out_path.name, stderr=err_path.name)
    print("\n=== "+name+" ===", flush=True)
    started = time.monotonic()
    with out_path.open("wb") as out, err_path.open("wb") as err:
        try:
            process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        except OSError as exc:
            err.write((str(exc)+"\n").encode())
            item.update(status="failed", exit_code=127, error=str(exc))
            return 127
        def copy_stream(source, saved, terminal):
            while True:
                data = source.read1(8192)
                if not data:
                    break
                saved.write(data); saved.flush()
                # A closed terminal pipe must not stop draining the child pipe.
                try:
                    terminal.buffer.write(data); terminal.flush()
                except (BrokenPipeError, OSError):
                    pass
            source.close()
        workers = [threading.Thread(target=copy_stream, args=(process.stdout,out,sys.stdout)),
                   threading.Thread(target=copy_stream, args=(process.stderr,err,sys.stderr))]
        for worker in workers: worker.start()
        try:
            code = process.wait()
        except KeyboardInterrupt:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            code = 130
        finally:
            for worker in workers: worker.join()
    item.update(status="passed" if code == 0 else "failed", exit_code=code,
                elapsed_seconds=round(time.monotonic()-started,3))
    return code


def stage_plan(root, racket, output, include_math=False, include_geometry=False,
               skip_examples=False):
    """Return the ordered plan, with 3D stages only when the r3 module is present."""
    py = sys.executable
    plan = [("structure", [py,"scribblings/check-structure.py","."]),
            ("learning-source", [py,"scribblings/check-learning-manual.py","."])]
    # Documentation layout checks do not rerender the examples.
    plan += [("frame-style-source", [py,"scribblings/check-frame-style.py","."]),
             ("frame-style-racket", [racket,"scribblings/check-frame-style.rkt"])]
    if not skip_examples:
        flags = (["--math"] if include_math else []) + (["--geometry"] if include_geometry else [])
        plan += [("existing-examples",[racket,"scribblings/check-examples.rkt",*flags]),
                 ("learning-examples",[racket,"scribblings/check-learning-examples.rkt"])]
    has_3d = (root/"scribblings/check-3d-manual.py").is_file()
    if has_3d:
        plan.append(("3d-source",[py,"scribblings/check-3d-manual.py","."]))
        if not skip_examples:
            plan.append(("3d-examples",[racket,"scribblings/check-3d-examples.rkt"]))
        # Reuse checked-in 3D figures from any Racket platform if their stored
        # sources and images validate. Only missing figures trigger rendering.
        if not (root/"scribblings/figures/3d-r3/manifest.json").is_file():
            plan.append(("3d-figures",[racket,"scribblings/render-3d-illustrations.rkt","--install"]))
        plan.append(("3d-images",[py,"scribblings/check-3d-manual.py",".","--rendered"]))
    plan += [("learning-figures",[racket,"scribblings/render-learning-illustrations.rkt","--install"]),
             ("learning-images",[py,"scribblings/check-learning-manual.py",".","--rendered"]),
             ("scribble",[racket,"tools/check-documentation.rkt",str(output)])]
    return plan


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination",nargs="?",default="slides-output/manual-learning-r4")
    parser.add_argument("--racket",default=os.environ.get("RACKET","racket"))
    parser.add_argument("--math",action="store_true")
    parser.add_argument("--geometry",action="store_true")
    parser.add_argument("--skip-examples",action="store_true",
                        help="skip example tests explicitly; the report records this")
    args=parser.parse_args()
    root=Path(__file__).resolve().parent.parent
    racket=shutil.which(args.racket)
    if racket is None:
        parser.error("Racket executable not found; pass --racket with its full path")
    destination=Path(args.destination).expanduser()
    if not destination.is_absolute(): destination=root/destination
    # Do not allow the HTML output to overwrite maintained source or the checkout.
    destination=destination.absolute()
    if destination == root or destination == root/"scribblings" or root/"scribblings" in destination.parents:
        parser.error("choose an output directory outside scribblings/")
    for path in [destination,*destination.parents]:
        if path.is_symlink(): parser.error("refusing a symbolic-link output path")
    destination=destination.resolve()
    if root in destination.parents and not (destination == root/"slides-output" or root/"slides-output" in destination.parents):
        parser.error("use slides-output/ for a destination inside the checkout")
    destination.mkdir(parents=True,exist_ok=True)
    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    logs=destination/"build-logs"/stamp
    logs.mkdir(parents=True,exist_ok=False)
    report={"schema":"animate-manual-build-v1", "started_utc":stamp,
            "root":str(root),"destination":str(destination),"racket":racket,
            "examples_skipped":args.skip_examples,"math_requested":args.math,
            "geometry_requested":args.geometry,"status":"running","stages":[]}
    report_file=logs/"build-report.json"
    code=0
    try:
        for name,command in stage_plan(root,racket,destination,args.math,args.geometry,args.skip_examples):
            code=run_stage(name,command,root,logs,report)
            report_file.write_text(json.dumps(report,indent=2)+"\n")
            if code: break
        report["status"]="passed" if code==0 else "failed"
        report["exit_code"]=code
    except BaseException as exc:
        report.update(status="interrupted" if isinstance(exc,KeyboardInterrupt) else "failed",
                      error=str(exc),exit_code=130 if isinstance(exc,KeyboardInterrupt) else 1)
        code=report["exit_code"]
        print(str(exc),file=sys.stderr)
    finally:
        report_file.write_text(json.dumps(report,indent=2)+"\n")
    print("\nBuild report: "+str(report_file))
    if code==0:
        print("Manual: "+str(destination/"animate/index.html"))
    else:
        print("Stopped at the failing stage; inspect its stderr log. Later stages were not run.",file=sys.stderr)
    return code if 0<=code<=255 else 1

if __name__=="__main__": raise SystemExit(main())
