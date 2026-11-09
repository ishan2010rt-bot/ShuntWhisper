#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ShuntWhisper Mobile Vision & Diagnostic Engine -- reference implementation
==========================================================================

Reads a passive evaporative-cooling patch with a Thermochromic Liquid Crystal
(TLC) film and infers VP-shunt patency from the upstream-to-downstream
temperature differential

        dT_UD = T_upstream - T_downstream            (patent flow  => > 0)

Pipeline (one frame)::

    BGR frame
      -> [S2] ArUco detect + cv2.cornerSubPix -> homography -> 800x400 canonical warp
      -> [S3] tone-curve (gamma) estimation, illumination flat-field, affine/von-Kries
              colour transform to D65 reference swatches -> HSV + CIE L*a*b*
      -> [S4] specular mask -> Gaussian-weighted ROI hue -> PCHIP T=f(H)
              -> dT_UD, SNR, confidence, hydration / range gating, flow class
    two timepoints (t = 23 s, 120 s) -> fused DiagnosticReport
    [S5] ShuntWhisperSession = finite state machine around the above
    [S1] GuidanceChecker = pose / distance / framing reticle logic (PnP)

Run ``python shuntwhisper_vision.py selftest`` for an end-to-end synthetic check.
Dependencies: numpy, scipy, opencv-contrib-python (>=4.7, tested with 5.0).

IMPORTANT NOTES ON ASSUMPTIONS (see docs/ShuntWhisper_Vision_Engine_Spec.md, sec. 1):
  * The default hue<->temperature table is a PLACEHOLDER consistent with
    ~28 deg Hue / degC.  It MUST be replaced by a per-TLC-lot calibration measured
    through *this same* normalisation pipeline (``HueTempCalibration.from_json``).
  * The synthetic renderer uses a reduced-order, phenomenological flow-asymmetry
    model (skewed Gaussian sink).  It validates the *vision chain*, not the
    biophysics; replace with CFD/COMSOL temperature fields for physics validation.
  * Research prototype -- not a validated medical device.
"""
from __future__ import annotations

import argparse
import dataclasses
import enum
import json
import logging
import math
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np
from scipy.interpolate import PchipInterpolator

log = logging.getLogger("shuntwhisper")

# =============================================================================
# 0. Small numeric helpers
# =============================================================================


def srgb_oetf(x: np.ndarray) -> np.ndarray:
    """Linear -> sRGB-encoded (IEC 61966-2-1)."""
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def srgb_eotf(x: np.ndarray) -> np.ndarray:
    """sRGB-encoded -> linear."""
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.04045, x / 12.92, np.power((x + 0.055) / 1.055, 2.4))


def ramp(x: float, good: float, bad: float) -> float:
    """Linear score: 1 at ``good``, 0 at ``bad`` (either direction), clipped."""
    if not np.isfinite(x):
        return 0.0
    return float(np.clip((x - bad) / (good - bad), 0.0, 1.0))


def wrap_hue(h_deg: np.ndarray | float, lo: float = -60.0) -> np.ndarray | float:
    """Unwrap a hue angle into [lo, lo+360) so the red wrap sits inside the axis."""
    return (np.asarray(h_deg) - lo) % 360.0 + lo


# =============================================================================
# 1. Configuration
# =============================================================================


@dataclass(frozen=True)
class Roi:
    name: str
    cx: float
    cy: float
    w: float
    h: float

    def bounds(self, W: int, H: int) -> Tuple[int, int, int, int]:
        x0 = max(0, int(round(self.cx - self.w / 2)))
        x1 = min(W, int(round(self.cx + self.w / 2)))
        y0 = max(0, int(round(self.cy - self.h / 2)))
        y1 = min(H, int(round(self.cy + self.h / 2)))
        return x0, y0, x1, y1


@dataclass(frozen=True)
class PatchGeometry:
    """Canonical (registered) patch layout. Units: canonical pixels (x = flow axis)."""

    canon_w: int = 800
    canon_h: int = 400
    px_per_mm: float = 10.0  # ASSUMPTION: 80 x 40 mm printed window
    marker_side: float = 60.0
    marker_centers: Dict[int, Tuple[float, float]] = field(
        default_factory=lambda: {0: (45.0, 45.0), 1: (755.0, 45.0), 2: (755.0, 355.0), 3: (45.0, 355.0)}
    )  # id -> centre; order TL, TR, BR, BL
    axis_y: float = 200.0
    foam_cx: float = 400.0
    x0: float = 87.0  # ROI offset from foam centre along flow axis: 8.7 mm * 10 px/mm
    foam_rect: Tuple[int, int, int, int] = (362, 162, 438, 238)  # 7.6 x 7.6 mm bare aperture
    tlc_rect: Tuple[int, int, int, int] = (100, 110, 700, 360)
    swatches: Dict[str, Tuple[int, int, int, int]] = field(
        default_factory=lambda: {
            "white": (170, 25, 270, 85),
            "gray": (290, 25, 390, 85),
            "black": (410, 25, 510, 85),
            "cyan": (530, 25, 580, 85),
            "magenta": (580, 25, 630, 85),
        }
    )
    # white-paper probes used to estimate illumination non-uniformity
    paper_probes: Tuple[Tuple[int, int, int, int], ...] = (
        (130, 358, 230, 392),
        (350, 358, 450, 392),
        (570, 358, 670, 392),
    )
    roi_w: float = 40.0  # 4.0 mm along flow axis
    roi_h: float = 60.0  # 6.0 mm transverse width

    @property
    def rois(self) -> Dict[str, Roi]:
        c, y = self.foam_cx, self.axis_y
        return {
            "upstream": Roi("upstream", c - self.x0, y, self.roi_w, self.roi_h),
            "downstream": Roi("downstream", c + self.x0, y, self.roi_w, self.roi_h),
            "lateral_ref": Roi("lateral_ref", c, y + 120.0, self.roi_w, self.roi_h),
            "substrate_ref": Roi("substrate_ref", c, y + 120.0, self.roi_w, self.roi_h),
            "evap_center": Roi("evap_center", c, y + 68.0, 80.0, 24.0),
        }

    def marker_corners(self, mid: int) -> np.ndarray:
        cx, cy = self.marker_centers[mid]
        s = self.marker_side / 2
        return np.array([[cx - s, cy - s], [cx + s, cy - s], [cx + s, cy + s], [cx - s, cy + s]], np.float32)


# Nominal LINEAR-light reflectances of the printed swatches under D65.
# ASSUMPTION: replace with spectrophotometer values per print lot.
SWATCH_REF_LINEAR: Dict[str, Tuple[float, float, float]] = {  # (R, G, B)
    "white": (0.95, 0.95, 0.95),
    "gray": (0.50, 0.50, 0.50),
    "black": (0.03, 0.03, 0.03),
    "cyan": (0.02, 0.38, 0.62),
    "magenta": (0.65, 0.02, 0.30),
}


@dataclass
class EngineConfig:
    # --- classification thresholds (spec Subsystem 4) ---
    eps_occlusion_c: float = 0.10
    thr_normal_flow_c: float = 0.35
    sigma_max_for_occlusion_c: float = 0.04  # occlusion call needs sigma_dT <= eps/2.5
    # --- specular / validity masks ---
    spec_v: float = 0.95
    spec_s: float = 0.15
    spec_dilate_px: int = 6  # bloom + PSF halo: the un-clipped skirt of a highlight is still colour-contaminated
    s_min: float = 0.25
    v_min: float = 0.15  # below this the TLC backing is "black" (needs matte backing <~1 % reflectance)
    min_valid_frac: float = 0.50
    max_dark_partial: float = 0.25
    max_spec_frac: float = 0.35
    hue_edge_margin_deg: float = 2.0
    corr_cell_px2: float = 16.0  # spatial correlation cell (demosaic + blur + JPEG)
    hue_se_floor_deg: float = 0.15
    # Systematic 1-sigma on dT_UD that averaging cannot remove (8-bit quantisation of the 5-patch colour
    # fit, lot calibration).  Measured ~0.03 degC on the synthetic bench -> set from a repeatability study.
    sys_sigma_dT_c: float = 0.03
    sigma_per_masked_frac_c: float = 0.5  # degC of added 1-sigma per unit specular-masked ROI fraction (bench-fit)
    # --- viewing-angle (Bragg cos-theta) correction ---
    angle_correction: bool = True
    kappa_angle_c: float = 13.75  # lambda/|dlambda/dT| ~ 550 nm / 40 nm per degC -- MEASURE per TLC lot
    nominal_distance_mm: float = 100.0
    sigma_angle_frac: float = 0.25  # 1-sigma uncertainty as a fraction of the applied correction (intrinsics, kappa)
    # --- hydration ---
    min_sink_drop_c: float = 1.50
    # --- QC gates ---
    max_reg_rms_px: float = 3.0
    min_sharpness: float = 0.06  # normalised Laplacian variance (sharp synthetic ~0.4; sigma_blur 2.5px ~0.05)
    good_sharpness: float = 0.20
    max_white_clip_frac: float = 0.02
    max_color_fit_rms: float = 0.06
    max_illum_nonuniformity: float = 0.35
    # --- timepoints ---
    t_transient_s: float = 23.0
    t_steady_s: float = 120.0


# =============================================================================
# 2. Hue -> temperature calibration (piecewise cubic, monotone)
# =============================================================================


class HueTempCalibration:
    """
    Monotone piecewise-cubic (PCHIP) mapping T = f(H), H in degrees (unwrapped, red wrap at -60).

    PCHIP is chosen over a natural cubic spline because it is C1 and *guaranteed
    monotone* between knots -- a natural spline can overshoot between sparse knots and
    create spurious non-monotone T(H), which would flip the sign of dT_UD.
    """

    DEFAULT_T = [25.0, 25.5, 26.0, 26.5, 27.0, 27.5, 28.0, 28.5, 29.0, 29.5, 30.0]
    DEFAULT_H = [0.0, 12.0, 26.0, 40.0, 54.0, 68.0, 83.0, 98.0, 113.0, 127.0, 140.0]  # ~24-30 deg/degC

    def __init__(self, temps_c: Sequence[float], hues_deg: Sequence[float], lot_id: str = "PLACEHOLDER"):
        t = np.asarray(temps_c, float)
        h = np.asarray(hues_deg, float)
        if len(t) < 4 or np.any(np.diff(t) <= 0) or np.any(np.diff(h) <= 0):
            raise ValueError("calibration knots must be >=4 and strictly increasing in both T and H")
        self.t, self.h, self.lot_id = t, h, lot_id
        self._h2t = PchipInterpolator(h, t, extrapolate=False)
        self._dh2t = self._h2t.derivative()
        self._t2h = PchipInterpolator(t, h, extrapolate=False)

    @property
    def h_min(self) -> float:
        return float(self.h[0])

    @property
    def h_max(self) -> float:
        return float(self.h[-1])

    @property
    def t_min(self) -> float:
        return float(self.t[0])

    @property
    def t_max(self) -> float:
        return float(self.t[-1])

    def hue_to_temp(self, h_deg: float) -> float:
        v = self._h2t(h_deg)
        return float(v) if np.isfinite(v) else float("nan")

    def slope_c_per_deg(self, h_deg: float) -> float:
        v = self._dh2t(np.clip(h_deg, self.h_min, self.h_max))
        return float(v)

    def temp_to_hue(self, t_c: np.ndarray | float) -> np.ndarray | float:
        return self._t2h(np.clip(t_c, self.t_min, self.t_max))

    @classmethod
    def default(cls) -> "HueTempCalibration":
        return cls(cls.DEFAULT_T, cls.DEFAULT_H)

    @classmethod
    def from_json(cls, path: str | Path) -> "HueTempCalibration":
        d = json.loads(Path(path).read_text())
        return cls(d["temps_c"], d["hues_deg"], d.get("lot_id", "UNKNOWN"))

    def to_json(self, path: str | Path) -> None:
        Path(path).write_text(
            json.dumps({"lot_id": self.lot_id, "temps_c": self.t.tolist(), "hues_deg": self.h.tolist()}, indent=2)
        )


# =============================================================================
# 3. Subsystem 2 -- fiducial detection, registration, rectification
# =============================================================================


class RegistrationError(RuntimeError):
    pass


@dataclass
class Registration:
    H: np.ndarray  # 3x3, image -> canonical
    rms_px: float  # RMS reprojection error of all 16 marker corners (canonical px)
    raw_per_canon: float  # raw pixels per canonical pixel (scale)
    centers_img: np.ndarray  # 4x2


def _make_detector() -> "cv2.aruco.ArucoDetector":
    dic = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    prm = cv2.aruco.DetectorParameters()
    prm.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_NONE  # we refine explicitly below
    return cv2.aruco.ArucoDetector(dic, prm)


_DETECTOR: Optional["cv2.aruco.ArucoDetector"] = None


def detect_fiducials(gray: np.ndarray, geom: PatchGeometry) -> Dict[int, np.ndarray]:
    """Return {id: 4x2 float32 sub-pixel corners (TL,TR,BR,BL in marker frame)}."""
    global _DETECTOR
    if _DETECTOR is None:
        _DETECTOR = _make_detector()
    corners, ids, _ = _DETECTOR.detectMarkers(gray)
    if ids is None:
        raise RegistrationError("no fiducials detected")
    found: Dict[int, np.ndarray] = {}
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.01)
    for c, i in zip(corners, ids.ravel()):
        i = int(i)
        if i not in geom.marker_centers or i in found:
            continue
        c = c.reshape(4, 1, 2).astype(np.float32)
        side = float(np.mean([np.linalg.norm(c[k, 0] - c[(k + 1) % 4, 0]) for k in range(4)]))
        win = int(np.clip(round(0.08 * side), 2, 8))
        found[i] = cv2.cornerSubPix(gray, c, (win, win), (-1, -1), crit).reshape(4, 2)
    missing = set(geom.marker_centers) - set(found)
    if missing:
        raise RegistrationError(f"missing fiducial ids {sorted(missing)}")
    return found


def _quad_center(c: np.ndarray) -> np.ndarray:
    """Projectively correct centre = intersection of the two diagonals (not the centroid)."""
    p1, p2, p3, p4 = c[0], c[2], c[1], c[3]
    d1, d2 = p2 - p1, p4 - p3
    t = np.linalg.solve(np.array([d1, -d2]).T, p3 - p1)
    return p1 + t[0] * d1


def register(gray: np.ndarray, geom: PatchGeometry) -> Registration:
    found = detect_fiducials(gray, geom)
    ids = sorted(geom.marker_centers)
    src = np.array([_quad_center(found[i]) for i in ids], np.float32)
    dst = np.array([geom.marker_centers[i] for i in ids], np.float32)
    H = cv2.getPerspectiveTransform(src, dst)
    # registration quality: reproject ALL 16 corners (independent of the 4 used for H)
    img_pts = np.concatenate([found[i] for i in ids]).reshape(-1, 1, 2).astype(np.float32)
    ref_pts = np.concatenate([geom.marker_corners(i) for i in ids])
    proj = cv2.perspectiveTransform(img_pts, H).reshape(-1, 2)
    rms = float(np.sqrt(np.mean(np.sum((proj - ref_pts) ** 2, axis=1))))
    # raw-px per canonical-px (pairwise centre distances)
    pairs = [(0, 1), (3, 2), (0, 3), (1, 2)]
    ratios = [
        np.linalg.norm(src[a] - src[b]) / np.linalg.norm(dst[a] - dst[b]) for a, b in pairs
    ]
    return Registration(H=H, rms_px=rms, raw_per_canon=float(np.mean(ratios)), centers_img=src)


def warp_to_canonical(bgr: np.ndarray, reg: Registration, geom: PatchGeometry) -> np.ndarray:
    """Rectify to 800x400 with the catheter axis along +x. Anti-alias when downsampling."""
    img = bgr
    if reg.raw_per_canon > 1.4:  # warpPerspective does not area-average; pre-filter to avoid aliasing
        s = 0.4 * reg.raw_per_canon
        img = cv2.GaussianBlur(bgr, (0, 0), s)
    return cv2.warpPerspective(
        img, reg.H, (geom.canon_w, geom.canon_h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE
    )


# =============================================================================
# 3b. Patch pose (PnP) and viewing-angle (Bragg cos-theta) correction
# =============================================================================
#
# lambda_peak = n * p(T) * cos(theta): the SAME physical temperature reads as a bluer (hotter) hue
# at an oblique viewing angle.  The up/down ROIs sit +-x0 from the optical axis, so any lateral camera
# offset delta gives them *different* theta and a spurious dT_UD:
#     d(dT_UD) ~ kappa * [cos th_up - cos th_dn],  kappa = lambda / |d lambda / dT|  (~14 degC per unit cos)
#   x0/d = 0.13, delta = 5 mm  ->  ~0.17 degC  (> the 0.1 degC occlusion threshold!)
# We therefore estimate the metric pose and subtract kappa * (cos th_nominal - cos th_actual) per ROI.


def solve_patch_pose(centers_img: np.ndarray, geom: PatchGeometry, intr: "CameraIntrinsics") -> Tuple[np.ndarray, np.ndarray]:
    """Planar PnP on the 4 fiducial centres. Returns (R, t): patch(mm) -> camera."""
    ids = sorted(geom.marker_centers)
    obj = np.array([[(geom.marker_centers[i][0] - geom.canon_w / 2) / geom.px_per_mm,
                     (geom.marker_centers[i][1] - geom.canon_h / 2) / geom.px_per_mm, 0.0] for i in ids], np.float64)
    ok, rvec, tvec = cv2.solvePnP(obj, np.asarray(centers_img, np.float64), intr.K(), None, flags=cv2.SOLVEPNP_ITERATIVE)
    if not ok:
        raise RegistrationError("PnP failed")
    R, _ = cv2.Rodrigues(rvec)
    return R, tvec.reshape(3)


def view_cosines(R: np.ndarray, t: np.ndarray, geom: PatchGeometry, d_nom_mm: float) -> Dict[str, Tuple[float, float]]:
    """{roi: (cos theta_actual, cos theta_nominal)}; nominal = camera on the foam axis at d_nom, fronto-parallel."""
    C = -R.T @ t
    out: Dict[str, Tuple[float, float]] = {}
    for n, r in geom.rois.items():
        P = np.array([(r.cx - geom.canon_w / 2) / geom.px_per_mm, (r.cy - geom.canon_h / 2) / geom.px_per_mm, 0.0])
        v = C - P
        vn = np.array([-P[0], -P[1], -d_nom_mm])
        out[n] = (abs(v[2]) / float(np.linalg.norm(v)), d_nom_mm / float(np.linalg.norm(vn)))
    return out


# =============================================================================
# 4. Quality metrics (motion blur, exposure)
# =============================================================================


def measure_sharpness(canon_bgr: np.ndarray, geom: PatchGeometry) -> Tuple[float, float]:
    """
    Motion/defocus blur metric on the *known-edge* fiducial regions of the canonical frame.

    Returns (laplacian_variance, normalised_sharpness).  Raw var(Laplacian) scales with
    contrast^2 and with exposure, so we normalise by the squared P98-P2 contrast of the same
    region -> comparable across illuminants.  sigma^2(Lap) / contrast^2.
    """
    gray = cv2.cvtColor(canon_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    lap = cv2.Laplacian(gray, cv2.CV_32F, ksize=3)
    mask = np.zeros(gray.shape, bool)
    s = int(geom.marker_side / 2) + 6
    for cx, cy in geom.marker_centers.values():
        mask[int(cy) - s : int(cy) + s, int(cx) - s : int(cx) + s] = True
    v = float(np.var(lap[mask]))
    p2, p98 = np.percentile(gray[mask], [2, 98])
    contrast = max(float(p98 - p2), 1.0)
    return v, v / contrast**2


# =============================================================================
# 5. Subsystem 3 -- radiometric & colorimetric normalisation
# =============================================================================


def _crop(img: np.ndarray, rect: Tuple[int, int, int, int], shrink: float = 0.2) -> np.ndarray:
    x0, y0, x1, y1 = rect
    dx, dy = int((x1 - x0) * shrink), int((y1 - y0) * shrink)
    return img[y0 + dy : y1 - dy, x0 + dx : x1 - dx]


@dataclass
class ColorTransform:
    gamma: float
    gamma_ok: bool
    M: np.ndarray  # 4x3 affine (rows 0-2: matrix, row 3: offset), linear->linear D65
    fit_rms: float  # RMS residual of affine fit on swatches (linear units)
    vk_rms: float  # RMS residual of diagonal von Kries alone
    white_enc_mean: float
    white_clip_frac: float
    white_lin_level: float  # raw (pre-normalisation) linear white level -> drift reference
    illum_nonuniformity: float  # (max-min)/mean of paper probes, before flat-fielding
    plane: np.ndarray  # flat-field plane coefficients (a,b,c): P = a + b*x + c*y


def _estimate_gamma(w: np.ndarray, g: np.ndarray, k: np.ndarray, ref_ratio: float) -> Tuple[float, bool]:
    """
    Camera tone curve  v = (g*L + b)^(1/gamma). The black-corrected gray/white ratio is
    illuminant-independent:  (G^gam - K^gam)/(W^gam - K^gam) = (0.50-0.03)/(0.95-0.03).
    Solve by bisection (the ratio is monotone decreasing in gamma).
    """
    def f(gam: float) -> float:
        num = np.power(g, gam) - np.power(k, gam)
        den = np.maximum(np.power(w, gam) - np.power(k, gam), 1e-9)
        return float(np.mean(num / den))

    lo, hi = 1.2, 3.4
    if not (f(hi) <= ref_ratio <= f(lo)):
        return 2.2, False
    for _ in range(50):
        mid = 0.5 * (lo + hi)
        lo, hi = (mid, hi) if f(mid) > ref_ratio else (lo, mid)
    return float(0.5 * (lo + hi)), True


class ColorNormalizer:
    """
    1. Linearise with a gamma solved from the gray/white/black swatches (self-calibrating tone curve).
    2. Flat-field: fit a plane to the paper-white probes and divide it out (illumination gradient).
    3. Chromatic adaptation: ridge-regularised 3x4 affine fit (swatch -> D65 reference), shrunk toward
       a diagonal von Kries (white-patch) solution so 5 patches cannot over-fit.
    4. Re-encode to sRGB and convert to HSV / CIE L*a*b*.
    """

    def __init__(self, geom: PatchGeometry, ridge: float = 2e-4):
        self.geom, self.ridge = geom, ridge

    def fit(self, canon_bgr: np.ndarray) -> Tuple[ColorTransform, np.ndarray]:
        g = self.geom
        enc = canon_bgr[..., ::-1].astype(np.float32) / 255.0  # RGB
        med = lambda im, r: np.median(_crop(im, r).reshape(-1, 3), axis=0)  # noqa: E731
        w_e, g_e, k_e = (med(enc, g.swatches[n]) for n in ("white", "gray", "black"))
        ref = SWATCH_REF_LINEAR
        ratio = (ref["gray"][0] - ref["black"][0]) / (ref["white"][0] - ref["black"][0])
        gamma, gamma_ok = _estimate_gamma(w_e, g_e, k_e, ratio)
        lin = np.power(np.clip(enc, 0, 1), gamma).astype(np.float32)

        # --- illumination plane from white-paper reference areas (white swatch + 3 probes) ---
        rects = [g.swatches["white"], *g.paper_probes]
        xs, ys, lv = [], [], []
        for r in rects:
            cx, cy = 0.5 * (r[0] + r[2]), 0.5 * (r[1] + r[3])
            xs.append(cx), ys.append(cy)
            lv.append(float(np.median(_crop(lin, r).mean(axis=2))))
        A = np.stack([np.ones(len(xs)), (np.array(xs) - 400) / 400, (np.array(ys) - 200) / 200], 1)
        plane, *_ = np.linalg.lstsq(A, np.array(lv), rcond=None)
        probes_lv = np.array(lv[1:])
        nonuni = float((probes_lv.max() - probes_lv.min()) / max(probes_lv.mean(), 1e-6))
        # normalise to the swatch band centre so the colour fit sees a unit-gain field
        yy, xx = np.mgrid[0 : g.canon_h, 0 : g.canon_w].astype(np.float32)
        P = plane[0] + plane[1] * (xx - 400) / 400 + plane[2] * (yy - 200) / 200
        P0 = plane[0] + plane[1] * (400 - 400) / 400 + plane[2] * (55 - 200) / 200
        lin_ff = lin * (P0 / np.maximum(P, 1e-3))[..., None]

        # --- colour fit on swatches (post flat-field) ---
        names = list(ref)
        meas = np.stack([med(lin_ff, g.swatches[n]) for n in names])  # n x 3
        refm = np.array([ref[n] for n in names], np.float64)  # n x 3
        W, K = meas[names.index("white")], meas[names.index("black")]
        s = (ref["white"][0] - ref["black"][0]) / np.maximum(W - K, 1e-6)
        M0 = np.zeros((4, 3))
        M0[:3, :3] = np.diag(s)
        M0[3] = ref["black"][0] - s * K
        Ah = np.hstack([meas, np.ones((len(names), 1))])
        M = np.linalg.solve(Ah.T @ Ah + self.ridge * np.eye(4), Ah.T @ refm + self.ridge * M0)
        fit_rms = float(np.sqrt(np.mean((Ah @ M - refm) ** 2)))
        vk_rms = float(np.sqrt(np.mean((Ah @ M0 - refm) ** 2)))

        white_rect = _crop(enc, g.swatches["white"], 0.0)
        clip_frac = float(np.mean(white_rect.max(axis=2) >= 0.99))
        ct = ColorTransform(
            gamma=gamma, gamma_ok=gamma_ok, M=M, fit_rms=fit_rms, vk_rms=vk_rms,
            white_enc_mean=float(w_e.mean()), white_clip_frac=clip_frac,
            white_lin_level=float(np.mean(np.power(w_e, gamma))), illum_nonuniformity=nonuni, plane=plane,
        )
        return ct, lin_ff

    @staticmethod
    def apply(ct: ColorTransform, lin_ff: np.ndarray) -> np.ndarray:
        """Return normalised, sRGB-encoded float32 RGB image in [0, 1]."""
        flat = lin_ff.reshape(-1, 3).astype(np.float64)
        out = np.clip(flat @ ct.M[:3] + ct.M[3], 0.0, 1.0)
        return srgb_oetf(out).astype(np.float32).reshape(lin_ff.shape)


def to_hsv_lab(rgb_enc: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """float32 RGB [0,1] -> HSV (H deg 0..360, S,V 0..1) and CIE L*a*b* (D65).
    Always float: 8-bit OpenCV hue (0..180) quantises at 2 deg ~ 0.07 degC and would waste the signal."""
    rgb = np.ascontiguousarray(rgb_enc, dtype=np.float32)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV), cv2.cvtColor(rgb, cv2.COLOR_RGB2Lab)


# =============================================================================
# 6. Subsystem 4 -- ROI signal extraction, temperature, flow inference
# =============================================================================


class RoiState(enum.Enum):
    IN_BAND = "in_band"
    BELOW_BAND = "below_band"  # hue at the red end: T <= T_min
    ABOVE_BAND = "above_band"  # hue at the blue end: T >= T_max
    DARK_WARM = "dark_warm"  # black, inferred isotropic clearing (T > T_max)
    DARK_COLD = "dark_cold"  # black, inferred below band (T < T_min)
    DARK_AMBIGUOUS = "dark_ambiguous"
    PARTIAL_DARK = "partial_dark"  # band edge cuts through ROI -> selection bias, unusable
    SPECULAR_LOST = "specular_lost"
    INVALID = "invalid"  # low saturation / no usable pixels


WARM_STATES = {RoiState.ABOVE_BAND, RoiState.DARK_WARM}
COLD_STATES = {RoiState.BELOW_BAND, RoiState.DARK_COLD}


@dataclass
class RoiStats:
    name: str
    state: RoiState
    hue_deg: float = float("nan")
    hue_se_deg: float = float("nan")
    temp_c: float = float("nan")
    temp_se_c: float = float("nan")
    valid_frac: float = 0.0
    dark_frac: float = 0.0
    spec_frac: float = 0.0
    spec_near_frac: float = 0.0  # specular fraction in the ROI + 24 px skirt
    n_eff: float = 0.0
    lab_hue_deg: float = float("nan")  # secondary, perceptually-uniform hue (diagnostic only)

    @property
    def exact(self) -> bool:
        return self.state is RoiState.IN_BAND


def specular_mask(hsv: np.ndarray, cfg: EngineConfig, raw_enc: Optional[np.ndarray] = None) -> np.ndarray:
    """Spec rule V>0.95 & S<0.15, plus sensor-well saturation in the raw frame, dilated for bloom."""
    m = (hsv[..., 2] > cfg.spec_v) & (hsv[..., 1] < cfg.spec_s)
    if raw_enc is not None:
        m |= raw_enc.min(axis=2) >= 0.985
    m = m.astype(np.uint8)
    if cfg.spec_dilate_px > 0:
        k = 2 * cfg.spec_dilate_px + 1
        m = cv2.dilate(m, np.ones((k, k), np.uint8))
    return m.astype(bool)


def analyze_roi(
    roi: Roi, hsv: np.ndarray, lab: np.ndarray, spec: np.ndarray, cal: HueTempCalibration, cfg: EngineConfig
) -> RoiStats:
    Hh, Ww = hsv.shape[:2]
    x0, y0, x1, y1 = roi.bounds(Ww, Hh)
    H, S, V = (hsv[y0:y1, x0:x1, k] for k in range(3))
    sp = spec[y0:y1, x0:x1]
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    # Gaussian spatial weighting; sigma = ROI/4 -> window edge at 2 sigma
    w = np.exp(-0.5 * (((xx - roi.cx) / (roi.w / 4)) ** 2 + ((yy - roi.cy) / (roi.h / 4)) ** 2))
    dark = (V < cfg.v_min) & ~sp
    valid = ~sp & (S >= cfg.s_min) & (V >= cfg.v_min)
    tot = float(w.sum())
    st = RoiStats(
        name=roi.name, state=RoiState.INVALID,
        valid_frac=float((w * valid).sum() / tot), dark_frac=float((w * dark).sum() / tot),
        spec_frac=float((w * sp).sum() / tot),
    )
    # The un-clipped additive skirt of a highlight still biases hue -> look beyond the ROI window too
    m = 24
    ex0, ey0, ex1, ey1 = max(0, x0 - m), max(0, y0 - m), min(Ww, x1 + m), min(Hh, y1 + m)
    st.spec_near_frac = float(spec[ey0:ey1, ex0:ex1].mean())
    if st.spec_frac > cfg.max_spec_frac:
        st.state = RoiState.SPECULAR_LOST
        return st
    if st.valid_frac < cfg.min_valid_frac:
        st.state = RoiState.DARK_AMBIGUOUS if st.dark_frac >= 0.5 else RoiState.INVALID
        return st
    if st.dark_frac > cfg.max_dark_partial:
        st.state = RoiState.PARTIAL_DARK
        return st

    wv = w * valid
    th = np.deg2rad(H)
    c, s_ = float((wv * np.cos(th)).sum()), float((wv * np.sin(th)).sum())
    sw = float(wv.sum())
    mean_h0 = math.degrees(math.atan2(s_, c))  # circular (Gaussian-weighted) mean
    # Real thermal gradient across the ROI is *signal*, not noise (a 0.03 degC/px slope would
    # otherwise inflate the circular std ~10x).  Fit a weighted plane to the hue residuals, take the
    # ROI-centre intercept as the estimate and the plane-residual scatter as the noise level.
    dh = (H - mean_h0 + 180.0) % 360.0 - 180.0
    A = np.stack([np.ones(dh.size), (xx - roi.cx).ravel(), (yy - roi.cy).ravel()], 1)
    sq = np.sqrt(wv.ravel())
    coef, *_ = np.linalg.lstsq(A * sq[:, None], dh.ravel() * sq, rcond=None)
    resid = dh.ravel() - A @ coef
    res_std = math.sqrt(float((wv.ravel() * resid**2).sum() / sw))
    mean_h = float(wrap_hue(mean_h0 + coef[0]))
    n_eff = (sw**2 / float((wv**2).sum())) / cfg.corr_cell_px2
    st.n_eff = n_eff
    st.hue_deg = mean_h
    st.hue_se_deg = math.hypot(1.25 * res_std / math.sqrt(max(n_eff, 1.0)), cfg.hue_se_floor_deg)
    a, b = lab[y0:y1, x0:x1, 1], lab[y0:y1, x0:x1, 2]
    st.lab_hue_deg = math.degrees(math.atan2(float((wv * b).sum()), float((wv * a).sum())))

    if mean_h < cal.h_min + cfg.hue_edge_margin_deg:
        st.state = RoiState.BELOW_BAND
    elif mean_h > cal.h_max - cfg.hue_edge_margin_deg:
        st.state = RoiState.ABOVE_BAND
    else:
        st.state = RoiState.IN_BAND
        st.temp_c = cal.hue_to_temp(mean_h)
        st.temp_se_c = abs(cal.slope_c_per_deg(mean_h)) * st.hue_se_deg
    return st


def resolve_dark_side(rois: Dict[str, RoiStats]) -> None:
    """
    A black TLC is ambiguous (T below the IR/red edge, or above the isotropic-clearing edge).
    Evaporation can only COOL, so a dark ROI that is *colder than an in-band substrate reference*
    is below band; if the substrate itself is dark/warm the whole patch is warm.  Mutates in place.
    """
    ref = rois.get("lateral_ref") or rois.get("substrate_ref")
    for r in rois.values():
        if r.state is not RoiState.DARK_AMBIGUOUS:
            continue
        if ref is None or ref.state in WARM_STATES | {RoiState.DARK_AMBIGUOUS, RoiState.INVALID}:
            r.state = RoiState.DARK_WARM
        elif ref.state is RoiState.IN_BAND and r.name not in ("substrate_ref", "lateral_ref"):
            r.state = RoiState.DARK_COLD
        elif ref.state in COLD_STATES or ref.state is RoiState.PARTIAL_DARK:
            r.state = RoiState.DARK_COLD


class FlowStatus(enum.Enum):
    OCCLUSION = "OCCLUSION_SUSPECTED"
    PATENT_LOW = "PATENT_LOW_FLOW"
    PATENT_NORMAL = "PATENT_NORMAL_FLOW"
    INDETERMINATE = "INDETERMINATE_RETEST"


def classify_flow(dT: float, sigma: float, cfg: EngineConfig) -> Tuple[FlowStatus, str, List[str]]:
    """Spec thresholds + uncertainty guards.  Returns (status, reason, flags)."""
    flags: List[str] = []
    eps, thr = cfg.eps_occlusion_c, cfg.thr_normal_flow_c
    if abs(dT - eps) < 2 * sigma or abs(dT - thr) < 2 * sigma:
        flags.append("NEAR_DECISION_BOUNDARY")
    if dT <= -eps:
        return FlowStatus.INDETERMINATE, "REVERSE_GRADIENT", flags + ["CHECK_PATCH_ORIENTATION"]
    if abs(dT) < eps:
        if sigma <= cfg.sigma_max_for_occlusion_c:
            return FlowStatus.OCCLUSION, "SYMMETRIC_PROFILE", flags
        return FlowStatus.INDETERMINATE, "LOW_SNR", flags
    if dT < 2 * sigma:
        return FlowStatus.INDETERMINATE, "LOW_SNR", flags
    return (FlowStatus.PATENT_LOW if dT < thr else FlowStatus.PATENT_NORMAL), "ASYMMETRIC_PROFILE", flags


# =============================================================================
# 7. Frame / report data structures and the engine
# =============================================================================


@dataclass
class FrameQA:
    reg_rms_px: float = float("nan")
    lap_var: float = float("nan")
    sharpness: float = float("nan")
    gamma: float = float("nan")
    gamma_ok: bool = False
    color_fit_rms: float = float("nan")
    vk_rms: float = float("nan")
    white_enc_mean: float = float("nan")
    white_clip_frac: float = float("nan")
    illum_nonuniformity: float = float("nan")
    white_lin_level: float = float("nan")
    passed: bool = False
    failures: List[str] = field(default_factory=list)


@dataclass
class FrameAnalysis:
    qa: FrameQA
    rois: Dict[str, RoiStats] = field(default_factory=dict)
    t_up_c: float = float("nan")
    t_down_c: float = float("nan")
    dT_ud_c: float = float("nan")
    dT_baseline_offset_c: float = 0.0
    sigma_dT_c: float = float("nan")
    snr_signal: float = float("nan")  # |dT| / sigma
    snr_resolution_db: float = float("nan")  # 20log10(eps / sigma): can we resolve the 0.1 degC decision line?
    sink_drop_c: float = float("nan")
    sink_drop_is_lower_bound: bool = False
    delta_t_evap_c: float = float("nan")
    delta_t_evap_definition: str = "T_lateral_ref - 0.5*(T_up + T_down)"
    angle_corr_c: Dict[str, float] = field(default_factory=dict)  # degC subtracted per ROI (Bragg cos-theta)
    pose: Dict[str, float] = field(default_factory=dict)  # distance_mm, tilt_deg
    status: FlowStatus = FlowStatus.INDETERMINATE
    reason: str = ""
    confidence: float = 0.0
    confidence_factors: Dict[str, float] = field(default_factory=dict)
    flags: List[str] = field(default_factory=list)
    debug: Dict[str, np.ndarray] = field(default_factory=dict, repr=False)


@dataclass
class DiagnosticReport:
    status: FlowStatus
    reason: str
    dT_ud_c: float
    confidence: float
    frames: Dict[float, FrameAnalysis]
    primary_t: float
    flags: List[str]
    message: str

    def to_dict(self) -> Dict[str, Any]:
        def fa(a: FrameAnalysis) -> Dict[str, Any]:
            return {
                "status": a.status.value, "reason": a.reason,
                "dT_ud_c": a.dT_ud_c, "sigma_dT_c": a.sigma_dT_c,
                "t_up_c": a.t_up_c, "t_down_c": a.t_down_c,
                "snr_signal": a.snr_signal, "snr_resolution_db": a.snr_resolution_db,
                "sink_drop_c": a.sink_drop_c, "sink_drop_is_lower_bound": a.sink_drop_is_lower_bound,
                "confidence_pct": a.confidence, "confidence_factors": a.confidence_factors,
                "flags": a.flags, "qa": dataclasses.asdict(a.qa),
                "rois": {k: {**dataclasses.asdict(v), "state": v.state.value} for k, v in a.rois.items()},
            }
        return {
            "status": self.status.value, "reason": self.reason, "dT_ud_c": self.dT_ud_c,
            "confidence_pct": self.confidence, "primary_timepoint_s": self.primary_t,
            "flags": self.flags, "message": self.message,
            "frames": {f"{t:g}s": fa(a) for t, a in self.frames.items()},
        }


class ShuntWhisperEngine:
    # confidence factor weights (geometric mean)
    _W = {"registration": 1.0, "sharpness": 1.0, "color_fit": 1.0, "exposure": 1.0, "illumination": 1.0,
          "specular": 1.0, "roi_validity": 1.0, "resolution_snr": 2.0, "illum_drift": 1.0}

    def __init__(self, geom: Optional[PatchGeometry] = None, cfg: Optional[EngineConfig] = None,
                 cal: Optional[HueTempCalibration] = None):
        self.geom = geom or PatchGeometry()
        self.cfg = cfg or EngineConfig()
        self.cal = cal or HueTempCalibration.default()
        self.norm = ColorNormalizer(self.geom)

    # -- one frame ---------------------------------------------------------------------------
    def analyze_frame(self, bgr: np.ndarray, baseline: Optional[FrameAnalysis] = None,
                      keep_debug: bool = False, intr: Optional["CameraIntrinsics"] = None) -> FrameAnalysis:
        cfg, geom = self.cfg, self.geom
        qa = FrameQA()
        fa = FrameAnalysis(qa=qa)
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        try:
            reg = register(gray, geom)
        except RegistrationError as e:
            qa.failures.append("REGISTRATION_FAILED")
            fa.reason, fa.flags = f"QC_REGISTRATION ({e})", ["QC_FAIL"]
            return fa
        qa.reg_rms_px = reg.rms_px
        canon = warp_to_canonical(bgr, reg, geom)
        qa.lap_var, qa.sharpness = measure_sharpness(canon, geom)
        ct, lin_ff = self.norm.fit(canon)
        qa.gamma, qa.gamma_ok = ct.gamma, ct.gamma_ok
        qa.color_fit_rms, qa.vk_rms = ct.fit_rms, ct.vk_rms
        qa.white_enc_mean, qa.white_clip_frac = ct.white_enc_mean, ct.white_clip_frac
        qa.illum_nonuniformity, qa.white_lin_level = ct.illum_nonuniformity, ct.white_lin_level

        if reg.rms_px > cfg.max_reg_rms_px:
            qa.failures.append("QC_REGISTRATION")
        if qa.sharpness < cfg.min_sharpness:
            qa.failures.append("QC_MOTION_BLUR")
        if qa.white_clip_frac > cfg.max_white_clip_frac or qa.white_enc_mean < 0.35:
            qa.failures.append("QC_EXPOSURE")
        if qa.color_fit_rms > cfg.max_color_fit_rms:
            qa.failures.append("QC_COLOR_FIT")
        if qa.illum_nonuniformity > cfg.max_illum_nonuniformity:
            qa.failures.append("QC_ILLUMINATION")
        qa.passed = not qa.failures

        rgb = self.norm.apply(ct, lin_ff)
        hsv, lab = to_hsv_lab(rgb)
        spec = specular_mask(hsv, cfg, canon[..., ::-1].astype(np.float32) / 255.0)
        fa.rois = {n: analyze_roi(r, hsv, lab, spec, self.cal, cfg) for n, r in geom.rois.items()}
        if cfg.angle_correction:
            self._apply_angle_correction(fa, reg, bgr.shape, intr)
        resolve_dark_side(fa.rois)
        if keep_debug:
            fa.debug = {"canonical": canon, "normalized": (rgb[..., ::-1] * 255).astype(np.uint8),
                        "spec_mask": spec.astype(np.uint8) * 255}
        self._infer(fa, baseline)
        if keep_debug:
            fa.debug["overlay"] = self._overlay(fa.debug["normalized"], fa)
        return fa

    # -- inference ---------------------------------------------------------------------------
    def _apply_angle_correction(self, fa: FrameAnalysis, reg: Registration, shape: Tuple[int, ...],
                                intr: Optional["CameraIntrinsics"]) -> None:
        h, w = shape[:2]
        intr = intr or CameraIntrinsics.from_fov(w, h)  # REAL builds: pass Camera2/AVFoundation intrinsics
        try:
            R, t = solve_patch_pose(reg.centers_img, self.geom, intr)
        except RegistrationError:
            fa.flags.append("POSE_FAILED_NO_ANGLE_CORRECTION")
            return
        fa.pose = {"distance_mm": float(np.linalg.norm(t)),
                   "tilt_deg": math.degrees(math.acos(min(1.0, abs(float(R[2, 2])))))}
        cos = view_cosines(R, t, self.geom, self.cfg.nominal_distance_mm)
        for n, st in fa.rois.items():
            ca, cn = cos[n]
            corr = self.cfg.kappa_angle_c * (cn - ca)  # oblique view reads HOT -> subtract
            fa.angle_corr_c[n] = corr
            if st.exact:
                st.temp_c -= corr

    def _infer(self, fa: FrameAnalysis, baseline: Optional[FrameAnalysis]) -> None:
        cfg = self.cfg
        up, dn = fa.rois["upstream"], fa.rois["downstream"]
        ev = fa.rois.get("evap_center")
        sub = fa.rois.get("lateral_ref") or fa.rois["substrate_ref"]

        # 1) hard QC gate -- no physiological verdict from a bad frame
        if fa.qa.failures:
            fa.status, fa.reason, fa.flags = FlowStatus.INDETERMINATE, fa.qa.failures[0], list(fa.qa.failures)
            fa.confidence = 0.0
            return

        # 2) hydration / sink gate.  An un-cooled patch is symmetric and would be mislabelled as
        #    OCCLUSION -- the most dangerous false call, so it is gated BEFORE flow classification.
        ok_sink, drop, is_lb, why = self._sink_check(ev, sub, up, dn)
        fa.sink_drop_c, fa.sink_drop_is_lower_bound = drop, is_lb
        fa.delta_t_evap_c = drop
        if why:
            fa.flags.append(why)
        if ok_sink is False:
            fa.status, fa.reason = FlowStatus.INDETERMINATE, "INSUFFICIENT_HYDRATION"
            return
        if ok_sink is None:
            fa.status, fa.reason = FlowStatus.INDETERMINATE, ("OUT_OF_RANGE_COLD" if why == "SUBSTRATE_BELOW_BAND" else "SINK_UNVERIFIABLE")
            return

        # 3) in-band requirement for the two flow ROIs
        for r in (up, dn):
            if not r.exact:
                if r.state in COLD_STATES:
                    reason = "OUT_OF_RANGE_COLD"
                elif r.state in WARM_STATES:
                    reason = "OUT_OF_RANGE_WARM"
                elif r.state is RoiState.SPECULAR_LOST:
                    reason = "SPECULAR_ROI"
                else:
                    reason = f"ROI_{r.name.upper()}_{r.state.value.upper()}"
                fa.status, fa.reason = FlowStatus.INDETERMINATE, reason
                fa.flags.append(f"{r.name}:{r.state.value}")
                return

        # 4) differential + uncertainty (+ optional manufacturing-asymmetry offset from the dry baseline)
        fa.t_up_c, fa.t_down_c = up.temp_c, dn.temp_c
        dT = up.temp_c - dn.temp_c
        var = up.temp_se_c**2 + dn.temp_se_c**2
        if baseline and baseline.rois["upstream"].exact and baseline.rois["downstream"].exact:
            b_up, b_dn = baseline.rois["upstream"], baseline.rois["downstream"]
            fa.dT_baseline_offset_c = b_up.temp_c - b_dn.temp_c
            dT -= fa.dT_baseline_offset_c
            var += b_up.temp_se_c**2 + b_dn.temp_se_c**2
            fa.flags.append("BASELINE_ASYMMETRY_SUBTRACTED")
        fa.dT_ud_c = dT
        var += cfg.sys_sigma_dT_c**2  # systematic floor (colour-matrix conditioning, lot calibration)
        var += (cfg.sigma_angle_frac * (fa.angle_corr_c.get("upstream", 0.0) - fa.angle_corr_c.get("downstream", 0.0))) ** 2
        # masked pixels => one-sided sampling + un-clipped highlight skirt => bias that grows with masked fraction
        var += (cfg.sigma_per_masked_frac_c * max(up.spec_frac, 0.0)) ** 2 + \
               (cfg.sigma_per_masked_frac_c * max(dn.spec_frac, 0.0)) ** 2
        fa.sigma_dT_c = math.sqrt(var)
        fa.snr_signal = abs(dT) / fa.sigma_dT_c
        fa.snr_resolution_db = 20 * math.log10(cfg.eps_occlusion_c / fa.sigma_dT_c)

        fa.status, fa.reason, fl = classify_flow(dT, fa.sigma_dT_c, cfg)
        fa.flags += fl
        if max(up.spec_near_frac, dn.spec_near_frac) > 0.0:
            fa.flags.append("SPECULAR_NEAR_ROI")  # un-clipped highlight skirt may bias hue
        fa.confidence, fa.confidence_factors = self._confidence(fa, baseline)

    def _sink_check(self, ev: Optional[RoiStats], sub: RoiStats,
                    up: Optional[RoiStats] = None, dn: Optional[RoiStats] = None) -> Tuple[Optional[bool], float, bool, str]:
        """Returns (adequate?, drop, drop_is_lower_bound, flag). adequate=None -> cannot verify."""
        cfg, cal = self.cfg, self.cal
        thr = cfg.min_sink_drop_c
        if sub.state in COLD_STATES or (sub.state is RoiState.PARTIAL_DARK and (math.isnan(sub.temp_c) or sub.temp_c <= cal.t_min + 0.8)):
            return None, float("nan"), False, "SUBSTRATE_BELOW_BAND"
        # 1) Primary definition per locked spec: ΔT_evap = T_lateral_ref - 0.5 * (T_up + T_down)
        if sub.exact and up and dn and up.exact and dn.exact:
            d = float(sub.temp_c - 0.5 * (up.temp_c + dn.temp_c))
            return d >= thr, d, False, ""
        # 2) Fallback to central/flanking TLC if available
        if ev and ev.state in COLD_STATES:  # sink centre colder than band edge -> strong sink
            return True, float("nan"), False, ""
        if ev and ev.exact and sub.exact:
            d = sub.temp_c - ev.temp_c
            return d >= thr, d, False, ""
        if ev and ev.exact and sub.state in WARM_STATES:  # substrate censored: drop >= T_max - T_ev
            d = cal.t_max - ev.temp_c
            return (True if d >= thr else False), d, True, ""
        if (ev and ev.state in WARM_STATES | {RoiState.DARK_AMBIGUOUS}) or (up and up.state in WARM_STATES and dn and dn.state in WARM_STATES):
            return False, 0.0, False, ""
        return None, float("nan"), False, "SINK_ROI_UNUSABLE"

    # -- confidence --------------------------------------------------------------------------
    def _confidence(self, fa: FrameAnalysis, baseline: Optional[FrameAnalysis]) -> Tuple[float, Dict[str, float]]:
        cfg, qa = self.cfg, fa.qa
        up, dn = fa.rois["upstream"], fa.rois["downstream"]
        drift = (abs(qa.white_lin_level / baseline.qa.white_lin_level - 1.0)
                 if baseline and baseline.qa.passed else 0.0)
        f = {
            "registration": ramp(qa.reg_rms_px, 0.4, cfg.max_reg_rms_px),
            "sharpness": ramp(qa.sharpness, cfg.good_sharpness, cfg.min_sharpness),
            "color_fit": ramp(qa.color_fit_rms, 0.01, cfg.max_color_fit_rms),
            "exposure": min(ramp(qa.white_enc_mean, 0.55, 0.35), ramp(qa.white_clip_frac, 0.0, cfg.max_white_clip_frac)),
            "illumination": ramp(qa.illum_nonuniformity, 0.05, cfg.max_illum_nonuniformity),
            "specular": ramp(max(up.spec_near_frac, dn.spec_near_frac), 0.0, 0.15),
            "roi_validity": ramp(min(up.valid_frac, dn.valid_frac), 0.90, cfg.min_valid_frac),
            # can the measurement resolve the 0.1 degC decision line?  0 dB (sigma = eps) -> 0, 12 dB -> 1
            "resolution_snr": ramp(fa.snr_resolution_db, 12.0, 0.0),
            "illum_drift": ramp(drift, 0.02, 0.15),
        }
        wsum = sum(self._W.values())
        logc = sum(self._W[k] * math.log(max(v, 1e-3)) for k, v in f.items()) / wsum
        return 100.0 * math.exp(logc), f

    # -- overlay ---------------------------------------------------------------------------------
    def _overlay(self, norm_bgr: np.ndarray, fa: FrameAnalysis) -> np.ndarray:
        img = norm_bgr.copy()
        for n, r in self.geom.rois.items():
            x0, y0, x1, y1 = r.bounds(self.geom.canon_w, self.geom.canon_h)
            st = fa.rois[n]
            col = (0, 200, 0) if st.exact else (0, 0, 255)
            cv2.rectangle(img, (x0, y0), (x1, y1), col, 1)
            txt = f"{n[:4]} {st.temp_c:.2f}C" if st.exact else f"{n[:4]} {st.state.value}"
            cv2.putText(img, txt, (x0 - 10, y0 - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.35, col, 1, cv2.LINE_AA)
        return img

    # -- two timepoints -> report -------------------------------------------------------------
    def diagnose(self, baseline_bgr: Optional[np.ndarray], samples: Dict[float, np.ndarray],
                 keep_debug: bool = False) -> DiagnosticReport:
        base = self.analyze_frame(baseline_bgr, keep_debug=keep_debug) if baseline_bgr is not None else None
        if base is not None:
            # baseline = dry, thermally equilibrated: substrate should NOT already be showing colour
            if base.rois and base.rois["substrate_ref"].exact:
                base.flags.append("BASELINE_ALREADY_IN_BAND")
        frames = {t: self.analyze_frame(img, base, keep_debug) for t, img in sorted(samples.items())}
        ts = sorted(frames)
        primary_t = ts[-1]  # steady state
        prim = frames[primary_t]
        flags = list(prim.flags)
        status, reason, conf, dT = prim.status, prim.reason, prim.confidence, prim.dT_ud_c
        if status is FlowStatus.INDETERMINATE and len(ts) > 1:  # fall back to transient with a penalty
            alt = frames[ts[0]]
            if alt.status is not FlowStatus.INDETERMINATE:
                status, reason, conf, dT, primary_t = alt.status, alt.reason, 0.6 * alt.confidence, alt.dT_ud_c, ts[0]
                flags.append("FALLBACK_TO_TRANSIENT")
        elif status is not FlowStatus.INDETERMINATE and len(ts) > 1:
            alt = frames[ts[0]]
            if alt.status is not FlowStatus.INDETERMINATE and alt.status is not status:
                conf *= 0.6
                flags.append(f"TIMEPOINT_DISAGREEMENT({alt.status.value}@{ts[0]:g}s)")
        msg = self._message(status, reason, dT, conf, prim)
        return DiagnosticReport(status, reason, dT, conf, frames, primary_t, flags, msg)

    @staticmethod
    def _message(status: FlowStatus, reason: str, dT: float, conf: float, a: FrameAnalysis) -> str:
        if status is FlowStatus.INDETERMINATE:
            hint = {
                "INSUFFICIENT_HYDRATION": "Evaporative sink did not form; re-apply 50 uL to the foam and repeat. NOT an occlusion finding.",
                "OUT_OF_RANGE_WARM": "TLC cleared (patch too warm). Let it equilibrate / retest.",
                "OUT_OF_RANGE_COLD": "TLC below band (too cold). Warm the patch / ambient and retest.",
                "QC_MOTION_BLUR": "Image blurred. Hold steady / use stand and retake.",
                "QC_REGISTRATION": "Fiducials poorly registered. Re-align and retake.",
                "QC_EXPOSURE": "Exposure out of range. Check torch / shroud.",
            }.get(reason, "Measurement not reliable; retest.")
            return f"INDETERMINATE ({reason}): {hint}"
        return (f"{status.value}: dT_UD = {dT:+.2f} degC (sigma {a.sigma_dT_c:.3f}), confidence {conf:.0f}%")


# =============================================================================
# 8. Subsystem 1 -- guidance reticle (distance / pitch / yaw / framing)
# =============================================================================


@dataclass
class CameraIntrinsics:
    fx: float
    fy: float
    cx: float
    cy: float

    @classmethod
    def from_fov(cls, w: int, h: int, hfov_deg: float = 69.0) -> "CameraIntrinsics":
        f = 0.5 * w / math.tan(math.radians(hfov_deg) / 2)
        return cls(f, f, w / 2, h / 2)

    def K(self) -> np.ndarray:
        return np.array([[self.fx, 0, self.cx], [0, self.fy, self.cy], [0, 0, 1]], np.float64)


@dataclass
class GuidanceResult:
    ok: bool
    distance_mm: float = float("nan")
    pitch_deg: float = float("nan")
    yaw_deg: float = float("nan")
    roll_deg: float = float("nan")
    center_offset: float = float("nan")  # fraction of frame diagonal
    messages: List[str] = field(default_factory=list)


class GuidanceChecker:
    """Planar PnP on the four fiducial centres -> metric pose; gates capture on pose tolerances."""

    def __init__(self, geom: PatchGeometry, target_mm: float = 100.0, dist_tol: float = 0.10,
                 tilt_tol_deg: float = 5.0, roll_tol_deg: float = 8.0, center_tol: float = 0.05,
                 edge_margin: float = 0.04):
        self.geom, self.target, self.dist_tol = geom, target_mm, dist_tol
        self.tilt_tol, self.roll_tol, self.center_tol, self.edge_margin = tilt_tol_deg, roll_tol_deg, center_tol, edge_margin

    def check(self, bgr: np.ndarray, intr: Optional[CameraIntrinsics] = None) -> GuidanceResult:
        h, w = bgr.shape[:2]
        intr = intr or CameraIntrinsics.from_fov(w, h)
        try:
            found = detect_fiducials(cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY), self.geom)
        except RegistrationError as e:
            return GuidanceResult(False, messages=[f"Show all 4 markers ({e})"])
        ids = sorted(self.geom.marker_centers)
        img_pts = np.array([_quad_center(found[i]) for i in ids], np.float64)
        obj = np.array([[(self.geom.marker_centers[i][0] - self.geom.canon_w / 2) / self.geom.px_per_mm,
                         (self.geom.marker_centers[i][1] - self.geom.canon_h / 2) / self.geom.px_per_mm, 0.0]
                        for i in ids], np.float64)
        ok, rvec, tvec = cv2.solvePnP(obj, img_pts, intr.K(), None, flags=cv2.SOLVEPNP_ITERATIVE)
        if not ok:
            return GuidanceResult(False, messages=["Pose estimation failed"])
        R, _ = cv2.Rodrigues(rvec)
        n = R[:, 2]
        pitch = math.degrees(math.atan2(n[1], n[2]))
        yaw = math.degrees(math.atan2(n[0], n[2]))
        roll = math.degrees(math.atan2(R[1, 0], R[0, 0]))
        dist = float(np.linalg.norm(tvec))
        allc = np.concatenate([found[i] for i in ids])
        c = allc.mean(axis=0)
        off = float(np.linalg.norm((c - [w / 2, h / 2])) / math.hypot(w, h))
        msgs: List[str] = []
        if dist > self.target * (1 + self.dist_tol):
            msgs.append("Move closer")
        elif dist < self.target * (1 - self.dist_tol):
            msgs.append("Move farther")
        if abs(pitch) > self.tilt_tol:
            msgs.append("Tilt phone " + ("down" if pitch > 0 else "up") + f" ({pitch:+.1f} deg)")
        if abs(yaw) > self.tilt_tol:
            msgs.append("Rotate phone " + ("left" if yaw > 0 else "right") + f" ({yaw:+.1f} deg)")
        if abs(roll) > self.roll_tol:
            msgs.append(f"Align patch with guide (roll {roll:+.1f} deg)")
        if off > self.center_tol:
            msgs.append("Center the patch")
        mx, my = self.edge_margin * w, self.edge_margin * h
        if allc[:, 0].min() < mx or allc[:, 0].max() > w - mx or allc[:, 1].min() < my or allc[:, 1].max() > h - my:
            msgs.append("Markers too close to the frame edge")
        return GuidanceResult(not msgs, dist, pitch, yaw, roll, off, msgs or ["Hold still"])


# =============================================================================
# 9. Subsystem 5 -- application finite state machine
# =============================================================================


class State(enum.Enum):
    IDLE = "STATE_IDLE"
    GUIDED_ALIGNMENT = "STATE_GUIDED_ALIGNMENT"
    BASELINE_CAPTURE = "STATE_BASELINE_CAPTURE"
    HYDRATION_TIMER = "STATE_HYDRATION_TIMER"
    SAMPLE_CAPTURE = "STATE_SAMPLE_CAPTURE"
    DIAGNOSTIC_REPORT = "STATE_DIAGNOSTIC_REPORT"


class ShuntWhisperSession:
    """
    Event-driven FSM.  The host app calls ``device_check`` once, then ``feed_frame`` for every
    preview frame and ``tick`` on a timer; the user's "50 uL delivered" button calls ``user_hydrated``.
    Time is injected (``clock``) so the machine is deterministic under test.
    """

    def __init__(self, engine: ShuntWhisperEngine, guidance: GuidanceChecker,
                 clock: Callable[[], float] = time.monotonic, stable_frames: int = 5,
                 capture_window_s: float = 1.0, max_baseline_retries: int = 3):
        self.engine, self.guidance, self.clock = engine, guidance, clock
        self.stable_frames, self.window = stable_frames, capture_window_s
        self.targets = [engine.cfg.t_transient_s, engine.cfg.t_steady_s]
        self.max_bl_retries = max_baseline_retries
        self.state = State.IDLE
        self.history: List[Tuple[float, State, str]] = []
        self.report: Optional[DiagnosticReport] = None
        self.baseline: Optional[np.ndarray] = None
        self.samples: Dict[float, np.ndarray] = {}
        self.last_guidance: Optional[GuidanceResult] = None
        self._ok_streak = 0
        self._bl_retries = 0
        self._t0: Optional[float] = None
        self._buf: List[Tuple[float, np.ndarray]] = []
        self._target_idx = 0

    def _go(self, s: State, why: str = "") -> None:
        log.info("FSM %s -> %s %s", self.state.value, s.value, why)
        self.history.append((self.clock(), s, why))
        self.state = s

    # IDLE -> GUIDED_ALIGNMENT
    def device_check(self, torch_ok: bool, manual_controls_ok: bool, storage_ok: bool = True) -> bool:
        if self.state is not State.IDLE:
            return False
        if torch_ok and manual_controls_ok and storage_ok:
            self._go(State.GUIDED_ALIGNMENT, "device ok")
            return True
        self.history.append((self.clock(), State.IDLE, "device check failed"))
        return False

    def user_hydrated(self) -> bool:
        if self.state is State.HYDRATION_TIMER and self._t0 is None:
            self._t0 = self.clock()
            return True
        return False

    def elapsed(self) -> Optional[float]:
        return None if self._t0 is None else self.clock() - self._t0

    def reset(self) -> None:
        self.__init__(self.engine, self.guidance, self.clock, self.stable_frames, self.window, self.max_bl_retries)

    def tick(self) -> None:
        """Time-only advance (no frame): HYDRATION_TIMER -> SAMPLE_CAPTURE and window close."""
        t = self.elapsed()
        if t is None:
            return
        if self.state is State.HYDRATION_TIMER and t >= self.targets[self._target_idx] - self.window:
            self._buf = []
            self._go(State.SAMPLE_CAPTURE, f"t={t:.1f}s window open for {self.targets[self._target_idx]:g}s")
        elif self.state is State.SAMPLE_CAPTURE and t >= self.targets[self._target_idx] + self.window:
            self._close_window()

    def feed_frame(self, bgr: np.ndarray) -> None:
        if self.state is State.GUIDED_ALIGNMENT:
            self.last_guidance = self.guidance.check(bgr)
            self._ok_streak = self._ok_streak + 1 if self.last_guidance.ok else 0
            if self._ok_streak >= self.stable_frames:
                self._go(State.BASELINE_CAPTURE, "aligned & stable")
                self._baseline(bgr)
        elif self.state is State.BASELINE_CAPTURE:
            self._baseline(bgr)
        elif self.state is State.SAMPLE_CAPTURE:
            self._buf.append((self.elapsed() or 0.0, bgr))
            self.tick()
        elif self.state is State.HYDRATION_TIMER:
            self.last_guidance = self.guidance.check(bgr)  # live drift warning only
            self.tick()

    def _baseline(self, bgr: np.ndarray) -> None:
        fa = self.engine.analyze_frame(bgr)
        if fa.qa.passed:
            self.baseline = bgr
            self._go(State.HYDRATION_TIMER, "baseline stored; waiting for 50 uL hydration")
        else:
            self._bl_retries += 1
            if self._bl_retries >= self.max_bl_retries:
                self._ok_streak = 0
                self._bl_retries = 0
                self._go(State.GUIDED_ALIGNMENT, f"baseline QC failed: {fa.qa.failures}")

    def _close_window(self) -> None:
        # choose the sharpest QC-passing frame of the burst
        best, best_s = None, -1.0
        for _, img in self._buf:
            try:
                reg = register(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), self.engine.geom)
                if reg.rms_px > self.engine.cfg.max_reg_rms_px:
                    continue
                s = measure_sharpness(warp_to_canonical(img, reg, self.engine.geom), self.engine.geom)[1]
            except RegistrationError:
                continue
            if s > best_s:
                best, best_s = img, s
        tgt = self.targets[self._target_idx]
        if best is not None:
            self.samples[tgt] = best
        self._target_idx += 1
        if self._target_idx < len(self.targets):
            self._go(State.HYDRATION_TIMER, f"{tgt:g}s captured" if best is not None else f"{tgt:g}s MISSED")
        else:
            if not self.samples:
                self._go(State.GUIDED_ALIGNMENT, "no usable sample frames; restart")
                return
            self.report = self.engine.diagnose(self.baseline, self.samples, keep_debug=True)
            self._go(State.DIAGNOSTIC_REPORT, self.report.message)


# =============================================================================
# 10. Synthetic data generator (validates the vision chain end-to-end)
# =============================================================================


@dataclass
class SynthScenario:
    name: str = "normal"
    flow_ml_min: float = 0.3
    t0_c: float = 31.0  # undisturbed surface temperature
    sink_amp_ss: float = 5.0  # steady-state evaporative drop under foam [degC]
    sink_amp_pk: float = 6.5  # transient peak near t = 23 s
    kappa_max: float = 0.20  # downstream skew at saturating flow  (phenomenological)
    q_half: float = 0.5  # mL/min at half-saturation
    sigma_px: float = 110.0
    sigma_y_px: float = 85.0
    illum_rgb: Tuple[float, float, float] = (1.0, 1.0, 1.0)
    illum_grad: Tuple[float, float] = (0.0, 0.0)  # fractional gain change across half-width / half-height
    specular: Tuple[Tuple[float, float, float, float], ...] = ()  # (cx, cy, radius_px, amplitude) canonical
    blur_sigma: float = 0.8
    motion_len: int = 0
    pose: Tuple[float, float, float] = (0.0, 0.0, 3.0)  # pitch, yaw, roll [deg]
    dist_mm: float = 100.0
    offset_mm: Tuple[float, float] = (0.0, 0.0)  # lateral camera displacement from the foam axis
    angle_kappa: float = 13.75  # degC per unit cos(theta): Bragg viewing-angle shift of the TLC (0 = off)
    exposure: float = 0.75
    jpeg_quality: int = 95
    cam_gamma: float = 2.2
    img_size: Tuple[int, int] = (2560, 1920)
    seed: int = 0

    def kappa(self, t: float) -> float:
        q = self.flow_ml_min
        return self.kappa_max * q / (q + self.q_half) * (1 - math.exp(-t / 15.0))

    def amp(self, t: float) -> float:
        if t <= 0:
            return 0.0  # dry baseline: no evaporative sink yet
        g = (t / 23.0) * math.exp(1 - t / 23.0)  # peaks (=1) at t = 23 s, then decays
        return (self.sink_amp_ss * (1 - math.exp(-t / 6.0)) + (self.sink_amp_pk - self.sink_amp_ss) * g)


_MIX = np.array([[0.92, 0.07, 0.01], [0.05, 0.90, 0.05], [0.01, 0.08, 0.91]])  # sensor cross-talk


def synth_temperature_field(geom: PatchGeometry, sc: SynthScenario, t: float, S: int = 1) -> np.ndarray:
    W, H = geom.canon_w * S, geom.canon_h * S
    x = (np.arange(W, dtype=np.float32) + 0.5) / S
    y = (np.arange(H, dtype=np.float32) + 0.5) / S
    xx, yy = np.meshgrid(x, y)
    k = sc.kappa(t)
    sig = np.where(xx > geom.foam_cx, sc.sigma_px * (1 + k), sc.sigma_px * (1 - k))  # swept downstream
    sink = sc.amp(t) * np.exp(-((xx - geom.foam_cx) ** 2) / (2 * sig**2)) * \
        np.exp(-((yy - geom.axis_y) ** 2) / (2 * sc.sigma_y_px**2))
    fixed_pattern = 0.02 * (xx - 400) / 300  # manufacturing asymmetry (degC)
    return (sc.t0_c - sink + fixed_pattern).astype(np.float32)


def synth_truth(geom: PatchGeometry, sc: SynthScenario, t: float, cal: HueTempCalibration) -> Dict[str, float]:
    T = synth_temperature_field(geom, sc, t)
    out = {}
    for n, r in geom.rois.items():
        x0, y0, x1, y1 = r.bounds(geom.canon_w, geom.canon_h)
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        w = np.exp(-0.5 * (((xx - r.cx) / (r.w / 4)) ** 2 + ((yy - r.cy) / (r.h / 4)) ** 2))
        out[n] = float((w * T[y0:y1, x0:x1]).sum() / w.sum())
    out["dT_ud"] = out["upstream"] - out["downstream"]
    return out


def _synth_pose(geom: PatchGeometry, sc: SynthScenario) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """K, R, t (patch[mm] -> camera) for the scenario's pose; patch centre sits on the optical axis
    except for the lateral camera offset ``offset_mm``."""
    Wi, Hi = sc.img_size
    K = CameraIntrinsics.from_fov(Wi, Hi).K()
    p, yw, r = (math.radians(a) for a in sc.pose)
    Rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    Ry = np.array([[math.cos(yw), 0, math.sin(yw)], [0, 1, 0], [-math.sin(yw), 0, math.cos(yw)]])
    Rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    R = Rz @ Ry @ Rx
    C = np.array([sc.offset_mm[0], sc.offset_mm[1], -sc.dist_mm], np.float64)
    t = -R @ C
    return K, R, t


def _homography_canon_to_image(geom: PatchGeometry, sc: SynthScenario) -> np.ndarray:
    K, R, t = _synth_pose(geom, sc)
    Hm = K @ np.column_stack([R[:, 0], R[:, 1], t])
    to_mm = np.array([[1 / geom.px_per_mm, 0, -geom.canon_w / 2 / geom.px_per_mm],
                      [0, 1 / geom.px_per_mm, -geom.canon_h / 2 / geom.px_per_mm], [0, 0, 1]])
    return Hm @ to_mm


def synth_angle_shift(geom: PatchGeometry, sc: SynthScenario, S: int, rect: Tuple[int, int, int, int]) -> np.ndarray:
    """Apparent-temperature shift  kappa*(cos th_nominal - cos th_actual)  per supersampled pixel of ``rect``."""
    _, R, t = _synth_pose(geom, sc)
    C = -R.T @ t
    x0, y0, x1, y1 = rect
    xs = (np.arange(x0, x1, dtype=np.float32) + 0.5) / S
    ys = (np.arange(y0, y1, dtype=np.float32) + 0.5) / S
    xx, yy = np.meshgrid((xs - geom.canon_w / 2) / geom.px_per_mm, (ys - geom.canon_h / 2) / geom.px_per_mm)
    cos_a = np.abs(C[2]) / np.sqrt((C[0] - xx) ** 2 + (C[1] - yy) ** 2 + C[2] ** 2)
    d = sc.dist_mm
    cos_n = d / np.sqrt(xx**2 + yy**2 + d**2)
    return (sc.angle_kappa * (cos_n - cos_a)).astype(np.float32)


def render_frame(geom: PatchGeometry, sc: SynthScenario, t: float, cal: HueTempCalibration,
                 rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """Render what a locked-exposure phone camera would record at time ``t`` (BGR uint8)."""
    rng = rng or np.random.default_rng(sc.seed)
    S = 2  # supersample the canonical scene
    W, H = geom.canon_w * S, geom.canon_h * S
    scene = np.full((H, W, 3), 0.95, np.float32)  # white paper

    # --- TLC film over black backing ---
    T = synth_temperature_field(geom, sc, t, S)
    x0, y0, x1, y1 = (v * S for v in geom.tlc_rect)
    Tt = T[y0:y1, x0:x1].copy()
    if sc.angle_kappa:
        Tt += synth_angle_shift(geom, sc, S, (x0, y0, x1, y1))  # what the camera *sees* (viewing-angle shift)
    hue = np.asarray(cal.temp_to_hue(Tt), np.float32)
    fade = np.clip((Tt - cal.t_min) / 0.2, 0, 1) * np.clip((cal.t_max - Tt) / 0.2, 0, 1)  # edge fade -> black
    hsv = np.dstack([hue, np.full_like(hue, 0.92), 0.70 * fade]).astype(np.float32)
    tlc_lin = srgb_eotf(cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)) + 0.004  # matte-black backing ~0.4 % reflectance
    scene[y0:y1, x0:x1] = tlc_lin
    # --- foam pad ---
    fx0, fy0, fx1, fy1 = (v * S for v in geom.foam_rect)
    scene[fy0:fy1, fx0:fx1] = 0.55 if t <= 0 else 0.38 + 0.05 * rng.standard_normal((fy1 - fy0, fx1 - fx0, 1))
    # --- swatches ---
    for n, (a, b, c, d) in geom.swatches.items():
        scene[b * S : d * S, a * S : c * S] = SWATCH_REF_LINEAR[n]
    # --- fiducials ---
    dic = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    ms = int(geom.marker_side * S)
    for mid, (cx, cy) in geom.marker_centers.items():
        m = cv2.aruco.generateImageMarker(dic, mid, ms).astype(np.float32) / 255.0
        m = 0.03 + (0.95 - 0.03) * m
        a, b = int(cx * S - ms / 2), int(cy * S - ms / 2)
        scene[b : b + ms, a : a + ms] = m[..., None]

    # --- illumination, sensor mixing, exposure, black level ---
    u = ((np.arange(W) + 0.5) / S - 400) / 400
    v = ((np.arange(H) + 0.5) / S - 200) / 200
    gain = 1 + sc.illum_grad[0] * u[None, :] + sc.illum_grad[1] * v[:, None]
    scene = scene * gain[..., None] * np.array(sc.illum_rgb, np.float32)
    scene = (scene.reshape(-1, 3) @ _MIX.T).reshape(scene.shape) * sc.exposure + 0.008
    for cx, cy, r, amp in sc.specular:  # additive specular highlights on the Mylar film
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        scene += amp * np.exp(-(((xx / S - cx) ** 2 + (yy / S - cy) ** 2) / (2 * (r / 2) ** 2)))[..., None]

    # --- projective camera ---
    # scene index i has its pixel centre at canonical coordinate (i + 0.5) / S  (OpenCV: centres at integers)
    Hc2i = _homography_canon_to_image(geom, sc) @ np.array([[1.0 / S, 0, 0.5 / S], [0, 1.0 / S, 0.5 / S], [0, 0, 1]])
    Wi, Hi = sc.img_size
    img = cv2.warpPerspective(scene, Hc2i, (Wi, Hi), flags=cv2.INTER_LINEAR,
                              borderMode=cv2.BORDER_CONSTANT, borderValue=(0.05, 0.05, 0.06))
    if sc.blur_sigma > 0:
        img = cv2.GaussianBlur(img, (0, 0), sc.blur_sigma)
    if sc.motion_len > 1:
        k = np.zeros((sc.motion_len, sc.motion_len), np.float32)
        k[sc.motion_len // 2, :] = 1.0 / sc.motion_len
        img = cv2.filter2D(img, -1, k)
    img = img + rng.standard_normal(img.shape).astype(np.float32) * (np.sqrt(np.maximum(img, 0) * 2e-4) + 0.002)
    enc = np.power(np.clip(img, 0, 1), 1 / sc.cam_gamma)
    bgr = (enc[..., ::-1] * 255 + 0.5).astype(np.uint8)
    if sc.jpeg_quality:
        bgr = cv2.imdecode(cv2.imencode(".jpg", bgr, [cv2.IMWRITE_JPEG_QUALITY, sc.jpeg_quality])[1], cv2.IMREAD_COLOR)
    return bgr


SCENARIOS: Dict[str, SynthScenario] = {
    "occluded": SynthScenario("occluded", flow_ml_min=0.0),
    "low_flow": SynthScenario("low_flow", flow_ml_min=0.10),
    "normal_flow": SynthScenario("normal_flow", flow_ml_min=0.45),
    "tungsten_normal": SynthScenario("tungsten_normal", flow_ml_min=0.45, illum_rgb=(1.35, 1.0, 0.62),
                                     illum_grad=(0.12, -0.06)),
    "specular_normal": SynthScenario("specular_normal", flow_ml_min=0.45,
                                     specular=((230.0, 195.0, 18.0, 3.0), (556.0, 208.0, 10.0, 3.0))),
    "dry_foam": SynthScenario("dry_foam", flow_ml_min=0.0, sink_amp_ss=0.8, sink_amp_pk=0.9),
    "too_cold": SynthScenario("too_cold", flow_ml_min=0.45, t0_c=27.0),
    "blurred": SynthScenario("blurred", flow_ml_min=0.45, blur_sigma=2.8),
    "off_center_low": SynthScenario("off_center_low", flow_ml_min=0.10, offset_mm=(7.0, 2.0), pose=(3.0, -4.0, 3.0)),
}


# =============================================================================
# 11. CLI / self-test
# =============================================================================


def _load(path: str) -> np.ndarray:
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(path)
    return img


def cmd_analyze(a: argparse.Namespace) -> int:
    cal = HueTempCalibration.from_json(a.cal) if a.cal else HueTempCalibration.default()
    eng = ShuntWhisperEngine(cal=cal)
    samples = {}
    if a.sample23:
        samples[23.0] = _load(a.sample23)
    if a.sample120:
        samples[120.0] = _load(a.sample120)
    rep = eng.diagnose(_load(a.baseline) if a.baseline else None, samples, keep_debug=bool(a.debug_dir))
    print(rep.message)
    d = rep.to_dict()
    if a.out:
        Path(a.out).write_text(json.dumps(d, indent=2, default=float))
    if a.debug_dir:
        out = Path(a.debug_dir)
        out.mkdir(parents=True, exist_ok=True)
        for t, fa in rep.frames.items():
            for k, im in fa.debug.items():
                cv2.imwrite(str(out / f"t{t:g}_{k}.png"), im)
    else:
        print(json.dumps({k: d[k] for k in ("status", "reason", "dT_ud_c", "confidence_pct", "flags")}, indent=2, default=float))
    return 0


def cmd_synth(a: argparse.Namespace) -> int:
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    cal = HueTempCalibration.default()
    geom = PatchGeometry()
    sc = SCENARIOS[a.scenario]
    for name, t in (("baseline", 0.0), ("sample23", 23.0), ("sample120", 120.0)):
        cv2.imwrite(str(out / f"{a.scenario}_{name}.png"), render_frame(geom, sc, t, cal))
    cal.to_json(out / "calibration_placeholder.json")
    print(f"wrote {a.scenario}_* to {out}")
    return 0


def run_selftest(save_dir: Optional[str] = None) -> int:
    logging.basicConfig(level=logging.WARNING)
    geom, cal = PatchGeometry(), HueTempCalibration.default()
    eng = ShuntWhisperEngine(geom, cal=cal)
    out = Path(save_dir) if save_dir else None
    if out:
        out.mkdir(parents=True, exist_ok=True)
    expect = {
        "occluded": (FlowStatus.OCCLUSION, None),
        "low_flow": (FlowStatus.PATENT_LOW, None),
        "normal_flow": (FlowStatus.PATENT_NORMAL, None),
        "tungsten_normal": (FlowStatus.PATENT_NORMAL, None),
        "specular_normal": (FlowStatus.PATENT_NORMAL, None),
        "dry_foam": (FlowStatus.INDETERMINATE, "INSUFFICIENT_HYDRATION"),
        "too_cold": (FlowStatus.INDETERMINATE, None),  # cold-range family
        "blurred": (FlowStatus.INDETERMINATE, "QC_MOTION_BLUR"),
        "off_center_low": (FlowStatus.PATENT_LOW, None),
    }
    fails = 0
    print(f"{'scenario':<16}{'truth dT':>9}{'est dT':>9}{'sigma':>7}{'conf%':>7}  status / reason")
    for name, (exp_status, exp_reason) in expect.items():
        sc = SCENARIOS[name]
        base = render_frame(geom, sc, 0.0, cal)
        s = {23.0: render_frame(geom, sc, 23.0, cal), 120.0: render_frame(geom, sc, 120.0, cal)}
        rep = eng.diagnose(base, s, keep_debug=out is not None)
        truth = synth_truth(geom, sc, rep.primary_t, cal)["dT_ud"]
        fa = rep.frames[rep.primary_t]
        ok = rep.status is exp_status
        if exp_reason:
            ok &= rep.reason == exp_reason
        if name == "too_cold":
            ok &= rep.reason == "OUT_OF_RANGE_COLD"
        if np.isfinite(fa.dT_ud_c) and rep.status is not FlowStatus.INDETERMINATE:
            tol = 0.12 if "tungsten" in name else (2.0 * fa.sigma_dT_c if "SPECULAR_NEAR_ROI" in fa.flags else 0.08)
            ok &= abs(fa.dT_ud_c - truth) < tol
            if "SPECULAR_NEAR_ROI" in fa.flags:
                ok &= rep.confidence < 80.0  # must be visibly down-weighted
        fails += not ok
        print(f"{name:<16}{truth:>9.3f}{fa.dT_ud_c:>9.3f}{fa.sigma_dT_c:>7.3f}{rep.confidence:>7.1f}  "
              f"{rep.status.value} / {rep.reason} {'OK' if ok else '<-- FAIL'}")
        if out:
            for t, f in rep.frames.items():
                if "overlay" in f.debug:
                    cv2.imwrite(str(out / f"{name}_t{t:g}_overlay.png"), f.debug["overlay"])

    # --- viewing-angle correction must matter: same frame, correction OFF -> large false dT_UD ---
    print("\nBragg viewing-angle correction (camera 7 mm off the foam axis, true low flow)")
    sc = SCENARIOS["off_center_low"]
    img = render_frame(geom, sc, 120.0, cal)
    truth = synth_truth(geom, sc, 120.0, cal)["dT_ud"]
    on = eng.analyze_frame(img)
    off = ShuntWhisperEngine(geom, dataclasses.replace(EngineConfig(), angle_correction=False), cal).analyze_frame(img)
    ok = abs(on.dT_ud_c - truth) < 0.08 and abs(off.dT_ud_c - truth) > 0.10
    fails += not ok
    print(f"   truth {truth:+.3f}  corrected {on.dT_ud_c:+.3f} ({on.status.value})  "
          f"uncorrected {off.dT_ud_c:+.3f} ({off.status.value})  {'OK' if ok else '<-- FAIL'}")

    # --- guidance reticle ---
    print("\nGuidance checks")
    gc = GuidanceChecker(geom)
    for label, kw, want in (("on-target", {}, True), ("yaw 20 deg", {"pose": (0, 20, 3)}, False),
                            ("too far 160 mm", {"dist_mm": 160}, False), ("roll 20 deg", {"pose": (0, 0, 20)}, False)):
        sc = dataclasses.replace(SCENARIOS["normal_flow"], **kw)
        r = gc.check(render_frame(geom, sc, 23.0, cal))
        ok = r.ok is want
        fails += not ok
        print(f"  {label:<16} ok={r.ok!s:<5} d={r.distance_mm:6.1f}mm pitch={r.pitch_deg:+5.1f} yaw={r.yaw_deg:+5.1f} "
              f"roll={r.roll_deg:+5.1f}  {r.messages}  {'OK' if ok else '<-- FAIL'}")

    # --- FSM end-to-end on a fake clock ---
    print("\nFSM session (normal flow)")
    now = [0.0]
    sc = SCENARIOS["normal_flow"]
    sess = ShuntWhisperSession(eng, gc, clock=lambda: now[0], stable_frames=3)
    sess.device_check(True, True)
    for _ in range(3):
        sess.feed_frame(render_frame(geom, sc, 0.0, cal))
        now[0] += 0.2
    sess.user_hydrated()
    t_hyd = now[0]
    for target in (23.0, 120.0):
        now[0] = t_hyd + target - sess.window + 0.01
        sess.tick()
        while sess.state is State.SAMPLE_CAPTURE:
            now[0] += 0.5
            sess.feed_frame(render_frame(geom, sc, sess.elapsed() or target, cal))
        now[0] = t_hyd + target + 1.01
        sess.tick()
    path = " -> ".join(h[1].value.replace("STATE_", "") for h in sess.history)
    print("  ", path)
    ok = sess.state is State.DIAGNOSTIC_REPORT and sess.report is not None \
        and sess.report.status is FlowStatus.PATENT_NORMAL
    fails += not ok
    print("  ", sess.report.message if sess.report else "no report", "OK" if ok else "<-- FAIL")
    print(f"\n{'ALL SELF-TESTS PASSED' if not fails else str(fails) + ' SELF-TEST FAILURE(S)'}")
    return 1 if fails else 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    p = argparse.ArgumentParser(description="ShuntWhisper vision & diagnostic engine (reference)")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("selftest", help="end-to-end synthetic validation")
    s.add_argument("--save-dir", default=None)
    s = sub.add_parser("synth", help="write synthetic frames for a scenario")
    s.add_argument("scenario", choices=sorted(SCENARIOS))
    s.add_argument("--outdir", default="synthetic_out")
    s = sub.add_parser("analyze", help="analyse real/synthetic frames")
    s.add_argument("--baseline")
    s.add_argument("--sample23")
    s.add_argument("--sample120")
    s.add_argument("--cal", help="per-lot hue->temperature calibration JSON")
    s.add_argument("--out", help="write JSON report")
    s.add_argument("--debug-dir", help="write canonical / normalised / overlay images")
    a = p.parse_args(argv)
    if a.cmd == "selftest":
        return run_selftest(a.save_dir)
    if a.cmd == "synth":
        return cmd_synth(a)
    return cmd_analyze(a)


if __name__ == "__main__":
    sys.exit(main())
