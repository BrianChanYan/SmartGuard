#!/usr/bin/env python3
import os
import time
import signal
import threading
from typing import Optional, Dict, List, Tuple
import shutil
from collections import deque, Counter

import cv2
import numpy as np
from flask import Flask, Response, request

app = Flask(__name__)

CAMERA = os.environ.get("CAMERA", "/dev/video0")
WIDTH  = int(os.environ.get("WIDTH", 640))
HEIGHT = int(os.environ.get("HEIGHT", 480))
FPS    = int(os.environ.get("FPS", 30))
QUAL   = int(os.environ.get("JPEG_QUALITY", 80))   # 1~100
BOUNDARY = os.environ.get("BOUNDARY", "frame")

DETECT_DOWNSCALE = float(os.environ.get("DETECT_DOWNSCALE", 0.4))
# Haar var
HAAR_SCALE_FACTOR = float(os.environ.get("HAAR_SCALE_FACTOR", 1.2))
HAAR_MIN_NEIGHBORS = int(os.environ.get("HAAR_MIN_NEIGHBORS", 4))
HAAR_MIN_SIZE = int(os.environ.get("HAAR_MIN_SIZE", 36))

ENABLE_RECOG = os.environ.get("ENABLE_RECOG", "1") == "1"
RECOG_DATA_DIR = os.environ.get("RECOG_DATA_DIR", "faces")
RECOG_THRESHOLD = float(os.environ.get("RECOG_THRESHOLD", 11))
RECOG_IMG_SIZE = int(os.environ.get("RECOG_IMG_SIZE", 96))

LOG_EVERY_SEC   = float(os.environ.get("LOG_EVERY_SEC", 5.0))
PRINT_STATS     = os.environ.get("PRINT_STATS", "1") == "1"
DETECT_EVERY_N  = int(os.environ.get("DETECT_EVERY_N", 1))
RECOG_EVERY_N   = int(os.environ.get("RECOG_EVERY_N", 2))

RECOG_MIN_SIDE  = int(os.environ.get("RECOG_MIN_SIDE", 48))
VOTE_WINDOW     = int(os.environ.get("VOTE_WINDOW", 5))
VOTE_REQUIRE    = int(os.environ.get("VOTE_REQUIRE", 3))

latest_jpeg_frame: Optional[bytes] = None
latest_bgr_frame: Optional[np.ndarray] = None
frame_lock = threading.Lock()
stop_event = threading.Event()

current_people: List[dict] = []
current_people_lock = threading.Lock()
CURRENT_EXPIRE_SEC = float(os.environ.get("CURRENT_EXPIRE_SEC", 1.5))

recognizer_lock = threading.Lock()
label2id: Dict[str, int] = {}
id2label: Dict[int, str] = {}
recognizer = None  # type: ignore

CASCADE_PATH = os.path.join(os.path.dirname(__file__), "haarcascade_frontalface_default.xml")
FACE_CASCADE = cv2.CascadeClassifier(CASCADE_PATH)
if FACE_CASCADE.empty():
    raise RuntimeError(f" Failed to load Haar cascade: {CASCADE_PATH}")
FACE_LOCK = threading.Lock()

def _ensure_opencv_contrib():
    if not hasattr(cv2, "face"):
        raise RuntimeError("OpenCV 'contrib' module uninstalld")

def open_capture() -> cv2.VideoCapture:
    try:
        os.system(f"v4l2-ctl -d {CAMERA} -p {FPS} >/dev/null 2>&1")
    except Exception:
        pass

    dev = 0 if str(CAMERA).endswith("0") else CAMERA
    cap = cv2.VideoCapture(dev, cv2.CAP_V4L2)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)
    cap.set(cv2.CAP_PROP_FPS,          FPS)
    cap.set(cv2.CAP_PROP_BUFFERSIZE,   4)

    for _ in range(5):
        ok, _ = cap.read()
        if ok: break
        time.sleep(0.02)
    return cap

def _iter_face_paths(root: str):
    if not os.path.isdir(root):
        return
    for label in sorted(os.listdir(root)):
        d = os.path.join(root, label)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if fn.lower().endswith((".jpg", ".jpeg", ".png")):
                yield label, os.path.join(d, fn)

def _prepare_face(gray: np.ndarray) -> np.ndarray:
    return cv2.resize(gray, (RECOG_IMG_SIZE, RECOG_IMG_SIZE), interpolation=cv2.INTER_AREA)

def train_recognizer_from_dir(root: str) -> Tuple[Optional[object], Dict[str, int], Dict[int, str]]:
    if not ENABLE_RECOG:
        return None, {}, {}
    _ensure_opencv_contrib()

    X: List[np.ndarray] = []
    y: List[int] = []
    l2i: Dict[str, int] = {}
    i2l: Dict[int, str] = {}
    next_id = 0

    for pair in _iter_face_paths(root) or []:
        label, path = pair
        try:
            img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
            if img is None:
                continue
            face_img = _prepare_face(img)
            X.append(face_img)
            if label not in l2i:
                l2i[label] = next_id
                i2l[next_id] = label
                next_id += 1
            y.append(l2i[label])
        except Exception as e:
            print(f"load {path}failed: {e}")

    if not X:
        print("no image found")
        return None, {}, {}

    rec = cv2.face.LBPHFaceRecognizer_create(radius=1, neighbors=8, grid_x=4, grid_y=4)
    rec.train(X, np.array(y))
    return rec, l2i, i2l

def reload_recognizer() -> bool:
    global recognizer, label2id, id2label
    try:
        rec, l2i, i2l = train_recognizer_from_dir(RECOG_DATA_DIR)
        with recognizer_lock:
            recognizer = rec
            label2id = l2i
            id2label = i2l
        return True
    except Exception as e:
        print(f"train failed: {e}")
        return False

def detection_loop():
    global latest_jpeg_frame, latest_bgr_frame, current_people

    cap = open_capture()
    if not cap.isOpened():
        print(f"Cannot open camera: {CAMERA}")
        return
    print(f"Camera opened {CAMERA} at {WIDTH}x{HEIGHT}@{FPS}")

    if ENABLE_RECOG:
        reload_recognizer()

    t_stat, frames = time.time(), 0
    last_log = time.time()
    frame_idx = 0

    faces_fullres: List[tuple] = []
    pred_hist = deque(maxlen=max(1, VOTE_WINDOW))  # multi frame vote

    while not stop_event.is_set():
        ok, frame = cap.read()
        if not ok:
            time.sleep(0.02)
            continue

        frames += 1
        frame_idx += 1

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        do_detect = (frame_idx % max(1, DETECT_EVERY_N) == 0)

        if 0 < DETECT_DOWNSCALE < 1.0:
            small = cv2.resize(
                gray,
                (int(gray.shape[1]*DETECT_DOWNSCALE), int(gray.shape[0]*DETECT_DOWNSCALE)),
                interpolation=cv2.INTER_AREA
            )
            scale = 1.0 / DETECT_DOWNSCALE
        else:
            small = gray
            scale = 1.0

        if do_detect:
            with FACE_LOCK:
                faces = FACE_CASCADE.detectMultiScale(
                    small,
                    scaleFactor=HAAR_SCALE_FACTOR,
                    minNeighbors=HAAR_MIN_NEIGHBORS,
                    minSize=(HAAR_MIN_SIZE, HAAR_MIN_SIZE),
                    flags=cv2.CASCADE_SCALE_IMAGE
                )
            faces_fullres = [(int(x*scale), int(y*scale), int(w*scale), int(h*scale)) for (x,y,w,h) in faces]

        do_recog = (frame_idx % max(1, RECOG_EVERY_N) == 0)

        with recognizer_lock:
            rec = recognizer
            labels = id2label.copy()

        faces_out = []
        best_for_vote = None
        faces_iter = sorted(faces_fullres, key=lambda b: b[2]*b[3], reverse=True)

        for idx, (x0, y0, w0, h0) in enumerate(faces_iter):
            cv2.rectangle(frame, (x0, y0), (x0+w0, y0+h0), (0, 255, 0), 2)
            name_text = "unknown"
            conf_val = None

            recognizable = (min(w0, h0) >= RECOG_MIN_SIDE)

            if rec is not None and do_recog and recognizable:
                crop = gray[y0:y0+h0, x0:x0+w0]
                if crop.size > 0:
                    face_img = _prepare_face(crop)
                    try:
                        pred_id, conf = rec.predict(face_img)
                        conf_val = float(conf)
                        if conf <= RECOG_THRESHOLD and pred_id in labels:
                            name_text = labels[pred_id]
                        else:
                            name_text = "unknown"
                    except Exception:
                        name_text = "unknown"

            # txt = f"{name_text}" + (f" ({conf_val:.1f})" if conf_val is not None else "")
            # cv2.putText(frame, txt, (x0, y0-6), cv2.FONT_HERSHEY_SIMPLEX,
            #             0.5, (0, 255, 0), 1, cv2.LINE_AA)
            
            if idx == 0:
                cv2.rectangle(frame, (x0, y0), (x0+w0, y0+h0), (0, 255, 0), 2)
                txt = f"{name_text}" + (f" ({conf_val:.1f})" if conf_val is not None else "")
                cv2.putText(frame, txt, (x0, y0-6), cv2.FONT_HERSHEY_SIMPLEX,
                            0.5, (0, 255, 0), 1, cv2.LINE_AA)

            faces_out.append({
                "label": name_text,
                "conf": conf_val,
                "bbox": [int(x0), int(y0), int(w0), int(h0)],
                "ts": time.time()
            })

            if idx == 0 and do_recog:
                best_for_vote = (name_text, conf_val)

        # update current_people
        with current_people_lock:
            current_people = faces_out

        if do_recog:
            pred_hist.append(best_for_vote if best_for_vote is not None else ("unknown", None))

        labels_in_window = [p[0] for p in pred_hist if p[0] != "unknown"]
        final_text = "unknown"
        if labels_in_window:
            c = Counter(labels_in_window)
            label_top, votes = c.most_common(1)[0]
            if votes >= VOTE_REQUIRE:
                confs = [p[1] for p in pred_hist if p[0] == label_top and p[1] is not None]
                final_text = f"{label_top} ({np.mean(confs):.1f})" if confs else label_top

        for (x0, y0, w0, h0) in faces_fullres:
            cv2.putText(frame, final_text, (x0, y0-6), cv2.FONT_HERSHEY_SIMPLEX,
                        0.6, (0, 255, 0), 2, cv2.LINE_AA)

        ok, buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), QUAL])
        if ok:
            with frame_lock:
                latest_jpeg_frame = buf.tobytes()
                latest_bgr_frame = frame

        now = time.time()
        if PRINT_STATS and (now - last_log) >= LOG_EVERY_SEC:
            dt = max(1e-6, now - t_stat)
            fps_now = frames / dt
            print(f"📷 stream fps ~ {fps_now:.1f} | faces: {len(faces_fullres)} | "
                  f"detect_every={DETECT_EVERY_N} | recog_every={RECOG_EVERY_N} | "
                  f"vote_window={VOTE_WINDOW}/{VOTE_REQUIRE}")
            last_log = now
            t_stat, frames = now, 0

    cap.release()
    print("detection loop stopped")

def mjpeg_generator():
    while not stop_event.is_set():
        with frame_lock:
            fb = latest_jpeg_frame
        if fb is None:
            time.sleep(0.02)
            continue
        yield (b"--" + BOUNDARY.encode() + b"\r\n"
               b"Content-Type: image/jpeg\r\n"
               b"Content-Length: " + str(len(fb)).encode() + b"\r\n\r\n" +
               fb + b"\r\n")
        time.sleep(max(0.0, 1.0 / FPS))

capture_thread = None
capture_event = threading.Event()
capture_state = {
    "running": False,
    "label": None,
    "interval_ms": 50,
    "target_count": 30,
    "saved": [],
    "face_only": True,
    "retrain_on_stop": True,
}

def _save_one_face(label: str, face_only: bool = True) -> Optional[str]:
    with frame_lock:
        frame = None if latest_bgr_frame is None else latest_bgr_frame.copy()
    if frame is None:
        return None

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    with FACE_LOCK:
        faces = FACE_CASCADE.detectMultiScale(
            gray,
            scaleFactor=HAAR_SCALE_FACTOR,
            minNeighbors=HAAR_MIN_NEIGHBORS,
            minSize=(HAAR_MIN_SIZE, HAAR_MIN_SIZE),
            flags=cv2.CASCADE_SCALE_IMAGE,
        )
    if len(faces) == 0:
        return None
    x, y, w, h = max(faces, key=lambda f: f[2]*f[3])
    roi = gray[y:y+h, x:x+w] if face_only else gray
    if roi.size == 0:
        return None

    img = _prepare_face(roi)
    save_dir = os.path.join(RECOG_DATA_DIR, label)
    os.makedirs(save_dir, exist_ok=True)
    fn = os.path.join(save_dir, f"cap_{int(time.time()*1000)}.jpg")
    cv2.imwrite(fn, img)
    return fn

def _capture_worker():
    label = capture_state["label"]
    interval = capture_state["interval_ms"] / 1000.0
    target = capture_state["target_count"]
    face_only = capture_state["face_only"]

    saved = []
    while not capture_event.is_set() and len(saved) < target:
        fn = _save_one_face(label, face_only)
        if fn:
            saved.append(fn)
        time.sleep(interval)

    capture_state["saved"] = saved
    capture_state["running"] = False

    if capture_state.get("retrain_on_stop", True):
        reload_recognizer()

@app.route("/recog/capture/start", methods=["POST"])
def api_capture_start():
    global capture_thread
    data = (request.get_json(silent=True) or {})
    label = request.args.get("label") or data.get("label")
    if not label:
        return {"ok": False, "error": "缺少 label"}, 400
    if capture_state["running"]:
        return {"ok": False, "error": "已在擷取中"}, 409

    capture_state.update({
        "running": True,
        "label": label,
        "interval_ms": int(request.args.get("interval_ms", data.get("interval_ms", 200))),
        "target_count": int(request.args.get("target_count", data.get("target_count", 20))),
        "face_only": (str(request.args.get("face", data.get("face", "true"))).lower() != "false"),
        "retrain_on_stop": (str(request.args.get("retrain", data.get("retrain", "true"))).lower() != "false"),
        "saved": [],
    })

    capture_event.clear()
    capture_thread = threading.Thread(target=_capture_worker, daemon=True)
    capture_thread.start()
    return {"ok": True, "running": True, "state": {k: v for k, v in capture_state.items() if k != "saved"}}

@app.route("/recog/capture/stop", methods=["POST"])
def api_capture_stop():
    global capture_thread
    if not capture_state["running"]:
        return {"ok": True, "running": False, "saved": capture_state.get("saved", [])}
    capture_event.set()
    if capture_thread and capture_thread.is_alive():
        capture_thread.join(timeout=2.0)
    return {"ok": True, "running": capture_state["running"], "saved": capture_state.get("saved", [])}

@app.route("/mjpeg")
def mjpeg():
    headers = {
        "Cache-Control": "no-cache, private",
        "Pragma": "no-cache",
        "Connection": "keep-alive",
    }
    return Response(
        mjpeg_generator(),
        mimetype=f"multipart/x-mixed-replace; boundary={BOUNDARY}",
        headers=headers,
    )

@app.get("/")
def ui_index():
    return Response(
        """
<!doctype html>
<meta charset="utf-8"/>
<title>Face Stream & Enrollment</title>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:980px;margin:20px auto;padding:0 16px}
  .row{display:flex;gap:16px;align-items:flex-start}
  .panel{flex:1;border:1px solid #ddd;border-radius:12px;padding:12px}
  label{display:block;margin:.5rem 0 .25rem}
  input[type=text],input[type=number]{width:100%;padding:.5rem;border:1px solid #ccc;border-radius:8px}
  button{padding:.6rem 1rem;border:1px solid #ccc;border-radius:10px;background:#f7f7f7;cursor:pointer}
  button:disabled{opacity:.5;cursor:not-allowed}
  .log{font-family:ui-monospace,Consolas,monospace;white-space:pre-wrap;background:#fafafa;border:1px dashed #ccc;border-radius:8px;padding:8px;min-height:80px}
  img{max-width:100%;border-radius:12px;border:1px solid #ddd}
</style>
<div class="row">
  <div class="panel">
    <h3>Live Stream</h3>
    <img id="stream" src="/mjpeg" alt="stream"/>
  </div>
  <div class="panel" style="max-width:360px">
    <h3>Enroll Controls</h3>
    <label>Label</label>
    <input id="label" type="text" placeholder="Alice"/>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
      <div>
        <label>Count</label>
        <input id="count" type="number" value="20" min="1"/>
      </div>
      <div>
        <label>Interval (ms)</label>
        <input id="interval" type="number" value="200" min="50"/>
      </div>
    </div>
    <label><input id="faceOnly" type="checkbox" checked/> Save face crop only</label>
    <label><input id="retrain" type="checkbox" checked/> Retrain on stop</label>
    <div style="display:flex; gap:8px; margin-top:8px">
      <button id="one">Capture 1</button>
      <button id="start">Start</button>
      <button id="stop" disabled>Stop</button>
    </div>
    <div style="margin-top:8px">
        <button id="labels">List Labels</button>
        <button id="clearAll" style="background:#fdd; border-color:#f99">Clear All</button>
    </div>
    <div class="log" id="log"></div>
  </div>
</div>
<script>
async function call(url, opts){
  try{
    const r = await fetch(url, {method:'POST', ...opts});
    const t = await r.text();
    try{ return JSON.parse(t); }catch{ return {status:r.status, raw:t}; }
  }catch(err){
    return {ok:false, error:String(err)};
  }
}
function val(id){ return document.getElementById(id).value; }
function checked(id){ return document.getElementById(id).checked; }
function log(x){ const el=document.getElementById('log'); el.textContent = (typeof x==='string'?x:JSON.stringify(x,null,2)) + '\\n' + el.textContent; }

const btnOne = document.getElementById('one');
const btnStart = document.getElementById('start');
const btnStop = document.getElementById('stop');

document.getElementById('labels').onclick = async()=>{
  const r = await fetch('/recog/labels');
  log(await r.json());
};

document.getElementById('clearAll').onclick = async()=>{
  const r = await call('/recog/clear');
  log(r);
};

btnOne.onclick = async()=>{
  const label = val('label');
  if(!label) return log('Please enter label');
  const face = checked('faceOnly');
  const retrain = checked('retrain');
  const r = await call(`/recog/capture?label=${encodeURIComponent(label)}&n=1&face=${face}&retrain=${retrain}`);
  log(r);
};

btnStart.onclick = async()=>{
  const label = val('label');
  if(!label) return log('Please enter label');
  const body = {
    label,
    target_count: parseInt(val('count')||'20',10),
    interval_ms: parseInt(val('interval')||'200',10),
    face: checked('faceOnly'),
    retrain: checked('retrain')
  };
  const r = await call('/recog/capture/start', {headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
  log(r);
  if(r.ok){ btnStart.disabled=true; btnStop.disabled=false; }
};

btnStop.onclick = async()=>{
  const r = await call('/recog/capture/stop');
  log(r);
  btnStart.disabled=false; btnStop.disabled=true;
};
</script>
""",
        mimetype="text/html",
    )

@app.get("/health")
def health():
    ok = latest_jpeg_frame is not None
    return {
        "ok": ok,
        "camera": CAMERA,
        "width": WIDTH, "height": HEIGHT, "fps": FPS,
        "quality": QUAL, "boundary": BOUNDARY,
        "recognition": ENABLE_RECOG,
        "labels": list(label2id.keys()),
        "threshold": RECOG_THRESHOLD,
        "detect_every_n": DETECT_EVERY_N,
        "recog_every_n": RECOG_EVERY_N,
        "log_every_sec": LOG_EVERY_SEC,
        "recog_min_side": RECOG_MIN_SIDE,
        "vote_window": VOTE_WINDOW,
        "vote_require": VOTE_REQUIRE,
    }, (200 if ok else 503)

@app.post("/recog/register")
def api_register():
    global capture_thread
    data = (request.get_json(silent=True) or {})
    label = request.args.get("label") or data.get("label")
    if not label:
        return {"ok": False, "error": "missing label"}, 400

    interval_ms  = int(request.args.get("interval_ms", data.get("interval_ms", 500)))
    target_count = int(request.args.get("target_count", data.get("target_count", 30)))
    face_only    = (str(request.args.get("face", data.get("face", "true"))).lower() != "false")
    retrain_stop = (str(request.args.get("retrain", data.get("retrain", "true"))).lower() != "false")
    wait_flag    = str(request.args.get("wait", data.get("wait", "false"))).lower() == "true"

    if capture_state.get("running"):
        return {"ok": False, "error": " "}, 409

    capture_state.update({
        "running": True,
        "label": label,
        "interval_ms": interval_ms,
        "target_count": target_count,
        "face_only": face_only,
        "retrain_on_stop": retrain_stop,
        "saved": [],
    })
    capture_event.clear()
    capture_thread = threading.Thread(target=_capture_worker, daemon=True)
    capture_thread.start()

    if wait_flag:
        expected_s = max(2.0, (target_count * (interval_ms / 1000.0)) * 1.8)
        timeout_s = float(request.args.get("timeout_s", data.get("timeout_s", expected_s)))
        t0 = time.time()
        while capture_state.get("running") and (time.time() - t0) < timeout_s:
            time.sleep(0.1)
        saved = capture_state.get("saved", [])
        return {
            "ok": True,
            "running": capture_state.get("running", False),
            "saved": saved,
            "count": len(saved),
            "labels": list(label2id.keys()),
            "state": {k: v for k, v in capture_state.items() if k != "saved"},
            "waited": True,
            "timeout_hit": capture_state.get("running", False)
        }, (200 if not capture_state.get("running") else 202)

    return {
        "ok": True,
        "running": True,
        "state": {k: v for k, v in capture_state.items() if k != "saved"},
        "note": "capture started"
    }, 202

@app.post("/recog/reload")
def api_reload():
    ok = reload_recognizer()
    return {"ok": ok, "labels": list(label2id.keys())}, (200 if ok else 500)

@app.post("/recog/enroll")
def api_enroll():
    label = None
    img = None

    if request.content_type and request.content_type.startswith("multipart"):
        label = request.form.get("label")
        file = request.files.get("image")
        if file:
            file_bytes = file.read()
            img_arr = np.frombuffer(file_bytes, np.uint8)
            img = cv2.imdecode(img_arr, cv2.IMREAD_GRAYSCALE)
    else:
        data = request.get_json(silent=True) or {}
        label = data.get("label")
        b64 = data.get("image")
        if isinstance(b64, str):
            if "," in b64:
                b64 = b64.split(",", 1)[1]
            import base64
            img_arr = np.frombuffer(base64.b64decode(b64), np.uint8)
            img = cv2.imdecode(img_arr, cv2.IMREAD_GRAYSCALE)

    if not label or img is None:
        return {"ok": False, "error": "缺少 label 或 image"}, 400

    save_dir = os.path.join(RECOG_DATA_DIR, label)
    os.makedirs(save_dir, exist_ok=True)
    fn = os.path.join(save_dir, f"{int(time.time()*1000)}.jpg")
    cv2.imwrite(fn, _prepare_face(img))

    ok = reload_recognizer()
    return {"ok": ok, "saved": fn, "labels": list(label2id.keys())}, (200 if ok else 500)

@app.get("/recog/labels")
def api_labels():
    return {"labels": list(label2id.keys()), "enabled": ENABLE_RECOG}

def _label_counts() -> Dict[str, int]:
    counts = {}
    if os.path.isdir(RECOG_DATA_DIR):
        for d in sorted(os.listdir(RECOG_DATA_DIR)):
            p = os.path.join(RECOG_DATA_DIR, d)
            if os.path.isdir(p):
                n = sum(1 for fn in os.listdir(p) if fn.lower().endswith((".jpg", ".jpeg", ".png")))
                counts[d] = n
    return counts

@app.post("/recog/delete")
def api_delete_label():
    label = request.args.get("label") or (request.get_json(silent=True) or {}).get("label")
    if not label:
        return {"ok": False, "error": "Missing label"}, 400

    target_dir = os.path.join(RECOG_DATA_DIR, label)
    if not os.path.isdir(target_dir):
        return {"ok": False, "error": f"label dne: {label}"}, 404

    global capture_thread
    if capture_state.get("running") and capture_state.get("label") == label:
        capture_event.set()
        if capture_thread and capture_thread.is_alive():
            capture_thread.join(timeout=2.0)
        capture_state["running"] = False

    try:
        shutil.rmtree(target_dir)
        os.makedirs(RECOG_DATA_DIR, exist_ok=True)
        reload_recognizer()
        return {
            "ok": True,
            "deleted": label,
            "labels": list(label2id.keys()),
            "counts": _label_counts()
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}, 500

@app.post("/recog/clear")
def api_clear_all():
    try:
        if os.path.isdir(RECOG_DATA_DIR):
            shutil.rmtree(RECOG_DATA_DIR)
        os.makedirs(RECOG_DATA_DIR, exist_ok=True)
        reload_recognizer()
        return {"ok": True, "labels": []}
    except Exception as e:
        return {"ok": False, "error": str(e)}, 500

@app.post("/recog/capture")
def api_capture():
    data = request.get_json(silent=True) or {}
    label = request.args.get("label") or data.get("label")
    n = int(request.args.get("n", data.get("n", 1)))
    do_retrain = (request.args.get("retrain", str(data.get("retrain", "true"))).lower() != "false")
    face_only = (request.args.get("face", str(data.get("face", "true"))).lower() != "false")

    if not label:
        return {"ok": False, "error": "Missing label"}, 400

    with frame_lock:
        frame = None if latest_bgr_frame is None else latest_bgr_frame.copy()
    if frame is None:
        return {"ok": False, "error": "currently no image available to retrieve"}, 503

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    with FACE_LOCK:
        faces = FACE_CASCADE.detectMultiScale(
            gray,
            scaleFactor=HAAR_SCALE_FACTOR,
            minNeighbors=HAAR_MIN_NEIGHBORS,
            minSize=(HAAR_MIN_SIZE, HAAR_MIN_SIZE),
            flags=cv2.CASCADE_SCALE_IMAGE,
        )
    if len(faces) == 0:
        return {"ok": False, "error": "No face detected"}, 404

    # get max face
    x, y, w, h = max(faces, key=lambda f: f[2]*f[3])

    save_dir = os.path.join(RECOG_DATA_DIR, label)
    os.makedirs(save_dir, exist_ok=True)

    saved: List[str] = []
    for i in range(max(1, n)):
        roi = gray[y:y+h, x:x+w] if face_only else gray
        if roi.size == 0:
            continue
        img = _prepare_face(roi)
        fn = os.path.join(save_dir, f"cap_{int(time.time()*1000)}_{i}.jpg")
        cv2.imwrite(fn, img)
        saved.append(fn)

    ok = True
    if do_retrain:
        ok = reload_recognizer()

    return {"ok": ok, "saved": saved, "count": len(saved), "labels": list(label2id.keys())}, (200 if ok else 500)

@app.get("/recog/current")
def api_current():
    now = time.time()
    with current_people_lock:
        people = [
            p for p in current_people
            if (now - float(p.get("ts", now))) <= CURRENT_EXPIRE_SEC
        ]
    return {"ok": True, "count": len(people), "people": people, "ts": now}

def _install_signals():
    def _stop(_sig, _frm):
        stop_event.set()
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

if __name__ == "__main__":
    _install_signals()
    th = threading.Thread(target=detection_loop, daemon=True)
    th.start()

    print(f" Server is running. Open:  http://<board_ip>:5000  (stream at /mjpeg)")
    print(" API: /recog/enroll, /recog/reload, /recog/labels, /recog/capture, /recog/capture/start, /recog/capture/stop, /recog/register, /recog/current, /recog/delete, /recog/clear, /health")
    app.run(host="0.0.0.0", port=5000, threaded=True, use_reloader=False)
