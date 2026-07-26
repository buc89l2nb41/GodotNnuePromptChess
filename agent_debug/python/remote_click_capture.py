import json
import os
import re
import socket
import subprocess
import sys
import time

import pyautogui


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT_EXE = os.path.abspath(os.path.join(ROOT, "..", "Godot_v4.6.2-stable_win64_console.exe"))
CHESS_PATH = os.path.abspath(os.path.join(ROOT))

CALIB_MOUSE_MISMATCH_PX = 5  # abort if OS mouse pos != Godot-reported mouse pos by more than this


def _readline_until(proc: subprocess.Popen, pattern: re.Pattern, timeout_s: float) -> re.Match:
    t0 = time.time()
    buf = ""
    while time.time() - t0 < timeout_s:
        chunk = proc.stdout.readline()
        if not chunk:
            time.sleep(0.05)
            continue
        buf += chunk
        m = pattern.search(buf)
        if m:
            return m
    raise TimeoutError("Timed out waiting for REMOTE_READY")


def _send_json(sock: socket.socket, obj: dict) -> dict:
    sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))
    data = b""
    while b"\n" not in data:
        try:
            chunk = sock.recv(65536)
        except socket.timeout as e:
            raise TimeoutError(f"Timed out waiting for response to cmd={obj.get('cmd')!r}") from e
        if not chunk:
            raise ConnectionError("socket closed")
        data += chunk
    line, _rest = data.split(b"\n", 1)
    return json.loads(line.decode("utf-8"))


def main() -> int:
    pyautogui.PAUSE = 0.08
    pyautogui.FAILSAFE = True
    step_capture = True  # one screenshot per click/step

    # Start capture session (so artifacts go to a session folder).
    subprocess.run(
        [
            GODOT_EXE,
            "--path",
            CHESS_PATH,
            "-s",
            "res://agent_debug/scripts/begin_capture_session.gd",
        ],
        check=True,
    )

    # Launch remote driver (windowed).
    proc = subprocess.Popen(
        [
            GODOT_EXE,
            "--path",
            CHESS_PATH,
            "-s",
            "res://agent_debug/scripts/ui_remote_driver.gd",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    try:
        m = _readline_until(proc, re.compile(r"REMOTE_READY port=(\d+)"), timeout_s=12.0)
        port = int(m.group(1))

        with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
            sock.settimeout(30)
            _send_json(sock, {"cmd": "hello"})

            step_i = 0

            # Calibration transform:
            #   actual_x = ax * godot_x + bx
            #   actual_y = ay * godot_y + by
            ax = ay = 1.0
            bx = by = 0.0

            def capture_step(label: str) -> None:
                nonlocal step_i
                if not step_capture:
                    return
                step_i += 1
                name = f"step_{step_i:02d}_{label}"
                print("capture_step:", name, flush=True)
                cap = _send_json(sock, {"cmd": "capture", "name": name})
                if not cap.get("ok", False):
                    raise RuntimeError(f"capture failed: {cap}")

            def click_xy(x: int, y: int, label: str) -> None:
                gx, gy = float(x), float(y)
                rx = int(ax * gx + bx)
                ry = int(ay * gy + by)
                print("click:", label, rx, ry, "(from", int(x), int(y), ")", flush=True)
                pyautogui.click(rx, ry)
                time.sleep(0.12)
                capture_step(label)

            def calibrate() -> None:
                nonlocal ax, ay, bx, by
                pts = _send_json(sock, {"cmd": "calib_points"})
                if not pts.get("ok", False):
                    raise RuntimeError(f"calib_points failed: {pts}")
                p1 = pts["p1"]
                p2 = pts["p2"]

                def sample(px: int, py: int, name: str) -> tuple[int, int]:
                    # Move mouse to intended point and read back from Godot.
                    pyautogui.moveTo(int(px), int(py), duration=0.0)
                    time.sleep(0.15)
                    os_pos = pyautogui.position()
                    mp = _send_json(sock, {"cmd": "mouse_pos"})
                    if not mp.get("ok", False):
                        raise RuntimeError(f"mouse_pos failed: {mp}")
                    dx = int(mp["x"]) - int(os_pos.x)
                    dy = int(mp["y"]) - int(os_pos.y)
                    if abs(dx) > CALIB_MOUSE_MISMATCH_PX or abs(dy) > CALIB_MOUSE_MISMATCH_PX:
                        raise RuntimeError(
                            "Calibration aborted: OS mouse pos != Godot mouse_pos "
                            f"(delta=({dx},{dy})px, tol={CALIB_MOUSE_MISMATCH_PX}px). "
                            "Likely DPI scaling / coordinate space mismatch. "
                            f"os_pos=({int(os_pos.x)},{int(os_pos.y)}) godot_pos=({int(mp['x'])},{int(mp['y'])})"
                        )
                    capture_step(f"calib_{name}")
                    return int(mp["x"]), int(mp["y"])

                o1x, o1y = sample(int(p1["x"]), int(p1["y"]), "p1")
                o2x, o2y = sample(int(p2["x"]), int(p2["y"]), "p2")

                i1x, i1y = float(p1["x"]), float(p1["y"])
                i2x, i2y = float(p2["x"]), float(p2["y"])
                # Solve per-axis affine transform.
                ax = (o2x - o1x) / (i2x - i1x) if i2x != i1x else 1.0
                ay = (o2y - o1y) / (i2y - i1y) if i2y != i1y else 1.0
                bx = o1x - ax * i1x
                by = o1y - ay * i1y
                print("calibration:", {"ax": ax, "bx": bx, "ay": ay, "by": by}, flush=True)

            def get_state() -> tuple[dict, dict]:
                msg = _send_json(sock, {"cmd": "targets"})
                if not msg.get("ok", False):
                    raise RuntimeError(f"targets failed: {msg}")
                return msg.get("window", {}), msg.get("targets", {})

            def wait_for_keys(keys: list[str], timeout_s: float = 5.0) -> dict:
                t0 = time.time()
                while time.time() - t0 < timeout_s:
                    _w, t = get_state()
                    if all(k in t for k in keys):
                        return t
                    time.sleep(0.10)
                # include a small diagnostic snapshot
                _w, t = get_state()
                diag = {k: t.get(k) for k in ["_popup_button_texts", "edit_button", "btn_clear"]}
                raise TimeoutError(f"Timed out waiting for keys: {keys}. diag={diag}")

            # 1) Click Edit button
            w, t = get_state()
            # Calibrate mapping before any real clicks (always first step).
            calibrate()

            # Focus window (real click) to ensure subsequent clicks land in Godot.
            if w:
                cx = int(w["x"] + w["w"] * 0.5)
                cy = int(w["y"] + w["h"] * 0.5)
                click_xy(cx, cy, "focus_window")

            # Open editor popup (real click).
            t = wait_for_keys(["edit_button"], timeout_s=6.0)
            click_xy(t["edit_button"]["x"], t["edit_button"]["y"], "click_edit_button")

            # Wait until popup targets appear.
            t = wait_for_keys(["btn_clear", "btn_bK", "btn_wK", "btn_wB", "btn_wN", "btn_apply"], timeout_s=8.0)
            # Popup controls are most sensitive to DPI scaling; apply window scale.
            def popup_visible() -> bool:
                _w, tt = get_state()
                return bool(tt.get("_popup_visible", False))

            def ensure_popup_open(label: str) -> None:
                # Popup can be closed by outside clicks; reopen deterministically.
                for i in range(3):
                    if popup_visible():
                        return
                    ttt = wait_for_keys(["edit_button"], timeout_s=6.0)
                    click_xy(ttt["edit_button"]["x"], ttt["edit_button"]["y"], f"open_editor_{label}_try{i+1}")
                    # Give UI a moment to materialize targets.
                    time.sleep(0.25)
                # Final attempt: wait for one known key to appear (will raise on timeout).
                wait_for_keys(["btn_clear"], timeout_s=3.0)

            def robust_popup_click(key: str, label: str, *, ok_if_popup_closes: bool = False) -> None:
                # Try a few small jitters around the provided center.
                tt = wait_for_keys([key], timeout_s=6.0)
                x = int(tt[key]["x"])
                y = int(tt[key]["y"])
                offsets = [(0, 0), (2, 0), (-2, 0), (0, 2), (0, -2), (3, 1), (-3, 1), (1, 3), (-1, -3)]
                for i, (dx, dy) in enumerate(offsets):
                    click_xy(x + dx, y + dy, f"{label}_try{i+1}")
                    # If this click accidentally closed the popup, reopen and continue trying.
                    if not popup_visible():
                        if ok_if_popup_closes:
                            return
                        ensure_popup_open("after_close")
                        wait_for_keys([key], timeout_s=6.0)
                    else:
                        return
                raise RuntimeError(f"failed to click popup target reliably: {key}")

            robust_popup_click("btn_clear", "click_clear")

            def pick_and_place(piece_btn: str, square_key: str, label: str) -> None:
                tt = wait_for_keys([piece_btn, square_key, "outside_popup"], timeout_s=6.0)
                robust_popup_click(piece_btn, f"pick_{label}")
                # Close popup first so the board receives the next click (PopupPanel is not exclusive).
                click_xy(tt["outside_popup"]["x"], tt["outside_popup"]["y"], f"close_popup_before_place_{label}")
                time.sleep(0.15)
                click_xy(tt[square_key]["x"], tt[square_key]["y"], f"place_{label}_{square_key}")
                # Popup may auto-close on outside clicks; reopen for the next action.
                ensure_popup_open("after_place")
                wait_for_keys(["btn_clear"], timeout_s=8.0)

            # Place only: black king, white king, white bishop, white knight.
            pick_and_place("btn_bK", "sq_e8", "bK")
            pick_and_place("btn_wK", "sq_e1", "wK")
            pick_and_place("btn_wB", "sq_c4", "wB")
            # Last piece: popup will likely close when clicking the board square; reopen before Apply.
            tt = wait_for_keys(["btn_wN", "sq_g1", "outside_popup"], timeout_s=6.0)
            robust_popup_click("btn_wN", "pick_wN")
            click_xy(tt["outside_popup"]["x"], tt["outside_popup"]["y"], "close_popup_before_place_wN")
            time.sleep(0.15)
            click_xy(tt["sq_g1"]["x"], tt["sq_g1"]["y"], "place_wN_sq_g1")

            # Apply editor (real click).
            ensure_popup_open("before_apply")
            tt = wait_for_keys(["btn_apply"], timeout_s=6.0)
            robust_popup_click("btn_apply", "click_apply", ok_if_popup_closes=True)

            # 3) Move knight g1 -> f3
            t = wait_for_keys(["sq_g1", "sq_f3"], timeout_s=6.0)
            click_xy(t["sq_g1"]["x"], t["sq_g1"]["y"], "click_g1")
            click_xy(t["sq_f3"]["x"], t["sq_f3"]["y"], "click_f3")

            # Final capture (redundant if step_capture is enabled, but kept for convenience).
            cap = _send_json(sock, {"cmd": "capture", "name": "python_real_click_flow_final"})
            print("final capture:", cap)

            _send_json(sock, {"cmd": "quit"})
        return 0
    except Exception as e:
        try:
            # Drain some driver output for diagnosis.
            if proc.stdout:
                out = proc.stdout.read()
                if out:
                    print("=== driver output ===")
                    print(out)
                    print("=== end driver output ===")
        finally:
            raise
    finally:
        try:
            proc.terminate()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())

