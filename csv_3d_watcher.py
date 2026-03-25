#!/usr/bin/env python3
"""
3D CSV plotter + 2-variable function fitting.

Reads CSV data from either one file or a folder of CSV files,
plots points (x, y, z), and fits an analytic function z = f(x, y).

CSV format:
- Any row with at least 3 numeric values is accepted.
- First 3 numeric columns are interpreted as Size, Iteration, Seconds.
- Header rows or non-numeric rows are skipped.
"""

from __future__ import annotations

import argparse
import csv
import math
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.widgets import TextBox


@dataclass
class Feature:
    name: str
    evaluator: Callable[[np.ndarray, np.ndarray], np.ndarray]


@dataclass
class FeatureModel:
    degree: int
    features: list[Feature]
    coef: np.ndarray

    def predict(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        dm = design_matrix_from_features(x, y, self.features)
        return dm @ self.coef

    def equation(self, precision: int = 4) -> str:
        chunks: list[str] = []
        for c, feature in zip(self.coef, self.features):
            if abs(c) < 1e-12:
                continue
            sign = "+" if c >= 0 else "-"
            mag = abs(c)
            chunks.append(f" {sign} {mag:.{precision}g}*{feature.name}")

        if not chunks:
            return "Seconds = 0"

        expr = "".join(chunks).strip()
        if expr.startswith("+"):
            expr = expr[1:].strip()
        return f"Seconds = {expr}"


def safe_exp(v: np.ndarray) -> np.ndarray:
    # Clip to avoid overflow
    return np.exp(np.clip(v, -50.0, 50.0))


def safe_log2_positive(v: np.ndarray) -> np.ndarray:
    out = np.zeros_like(v, dtype=float)
    mask = v > 0.0
    out[mask] = np.log2(v[mask])
    return out


def safe_self_power(v: np.ndarray) -> np.ndarray:
    # v^v for v > 0, else 0
    out = np.zeros_like(v, dtype=float)
    mask = v > 0.0
    out[mask] = safe_exp(v[mask] * np.log(v[mask]))
    return out


def feature_library(degree: int, exp_bases: list[float]) -> list[Feature]:
    eps = 1e-9
    feats: list[Feature] = [
        Feature("1", lambda x, y: np.ones_like(x, dtype=float)),
        Feature("Size", lambda x, y: x),
        Feature("Iteration", lambda x, y: y),
    ]

    # Polynomial powers and mixed terms up to chosen degree
    for p in range(2, degree + 1):
        feats.append(Feature(f"Size^{p}", lambda x, y, p=p: x**p))
        feats.append(Feature(f"Iteration^{p}", lambda x, y, p=p: y**p))

    for total in range(2, degree + 1):
        for px in range(total - 1, 0, -1):
            py = total - px
            feats.append(
                Feature(
                    f"Size^{px}*Iteration^{py}",
                    lambda x, y, px=px, py=py: (x**px) * (y**py),
                )
            )

    # Extra operators/features requested
    feats.extend(
        [
            Feature("Size*Iteration", lambda x, y: x * y),
            Feature("Size/(Iteration+eps)", lambda x, y, eps=eps: x / (y + eps)),
            Feature("Iteration/(Size+eps)", lambda x, y, eps=eps: y / (x + eps)),
            Feature("log2(|Size|+1)", lambda x, y: np.log2(np.abs(x) + 1.0)),
            Feature("log2(|Iteration|+1)", lambda x, y: np.log2(np.abs(y) + 1.0)),
            Feature("log2(Size)", lambda x, y: safe_log2_positive(x)),
            Feature("log2(Iteration)", lambda x, y: safe_log2_positive(y)),
            Feature("Size^Size", lambda x, y: safe_self_power(x)),
            Feature("Iteration^Iteration", lambda x, y: safe_self_power(y)),
        ]
    )

    for base in exp_bases:
        if base <= 0.0 or abs(base - 1.0) < 1e-12:
            continue
        ln_base = math.log(base)
        feats.append(
            Feature(
                f"{base}^Size",
                lambda x, y, ln_base=ln_base: safe_exp(ln_base * x),
            )
        )
        feats.append(
            Feature(
                f"{base}^Iteration",
                lambda x, y, ln_base=ln_base: safe_exp(ln_base * y),
            )
        )

    return feats


def design_matrix_from_features(
    x: np.ndarray,
    y: np.ndarray,
    features: list[Feature],
) -> np.ndarray:
    cols: list[np.ndarray] = []
    for feat in features:
        col = feat.evaluator(x, y)
        col = np.asarray(col, dtype=float)
        col = np.where(np.isfinite(col), col, 0.0)
        cols.append(col)
    return np.column_stack(cols)


def fit_feature_model(
    x: np.ndarray,
    y: np.ndarray,
    z: np.ndarray,
    degree: int,
    exp_bases: list[float],
    ridge_alpha: float,
) -> FeatureModel:
    features = feature_library(degree, exp_bases)
    dm = design_matrix_from_features(x, y, features)

    # Robust least-squares solve that also handles underdetermined systems.
    # If ridge_alpha > 0, solve the augmented system:
    # [X          ] c ~= [z]
    # [sqrt(a) * I]      [0]
    # This avoids explicit X^T X inversion and is more stable.
    if ridge_alpha > 0.0:
        n_features = dm.shape[1]
        reg_block = math.sqrt(ridge_alpha) * np.eye(n_features)
        aug_x = np.vstack([dm, reg_block])
        aug_y = np.concatenate([z, np.zeros(n_features, dtype=float)])
        coef, *_ = np.linalg.lstsq(aug_x, aug_y, rcond=None)
    else:
        coef, *_ = np.linalg.lstsq(dm, z, rcond=None)

    return FeatureModel(degree=degree, features=features, coef=coef)


def r2_score(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    ss_res = np.sum((y_true - y_pred) ** 2)
    ss_tot = np.sum((y_true - np.mean(y_true)) ** 2)
    if ss_tot <= 1e-12:
        return 1.0 if ss_res <= 1e-12 else 0.0
    return 1.0 - (ss_res / ss_tot)


def parse_csv_points(path: Path) -> list[tuple[float, float, float]]:
    points: list[tuple[float, float, float]] = []
    with path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            numeric: list[float] = []
            for item in row:
                s = item.strip()
                if not s:
                    continue
                try:
                    numeric.append(float(s))
                except ValueError:
                    # Skip non-numeric cell
                    continue
            if len(numeric) >= 3 and all(math.isfinite(v) for v in numeric[:3]):
                points.append((numeric[0], numeric[1], numeric[2]))
    return points


def list_csv_files(folder: Path, pattern: str, recursive: bool) -> list[Path]:
    if recursive:
        files = sorted(p for p in folder.rglob(pattern) if p.is_file())
    else:
        files = sorted(p for p in folder.glob(pattern) if p.is_file())
    return files


def resolve_input_csv_files(path: Path, pattern: str, recursive: bool) -> list[Path]:
    if not path.exists():
        raise FileNotFoundError(f"Path does not exist: {path}")

    if path.is_file():
        if path.suffix.lower() != ".csv":
            raise ValueError(f"Input file is not a CSV: {path}")
        return [path]

    if path.is_dir():
        return list_csv_files(path, pattern, recursive)

    raise ValueError(f"Unsupported path type: {path}")


def load_all_points(files: list[Path]) -> np.ndarray:
    rows: list[tuple[float, float, float]] = []
    for p in files:
        rows.extend(parse_csv_points(p))
    if not rows:
        return np.empty((0, 3), dtype=float)
    return np.array(rows, dtype=float)


def update_plot(
    ax,
    points: np.ndarray,
    model: FeatureModel | None,
    files_count: int,
    show_surface: bool,
) -> None:
    ax.clear()

    if points.shape[0] == 0:
        ax.set_title("No valid points found in CSV files")
        ax.set_xlabel("Size")
        ax.set_ylabel("Iteration")
        ax.set_zlabel("Seconds")
        return

    x = points[:, 0]
    y = points[:, 1]
    z = points[:, 2]

    ax.scatter(x, y, z, c="royalblue", alpha=0.85, label="CSV points")

    if model is not None and show_surface:
        x_min, x_max = np.min(x), np.max(x)
        y_min, y_max = np.min(y), np.max(y)

        # Avoid degenerate grids
        if abs(x_max - x_min) < 1e-12:
            x_min -= 1.0
            x_max += 1.0
        if abs(y_max - y_min) < 1e-12:
            y_min -= 1.0
            y_max += 1.0

        gx, gy = np.meshgrid(
            np.linspace(x_min, x_max, 35),
            np.linspace(y_min, y_max, 35),
        )
        gz = model.predict(gx.ravel(), gy.ravel()).reshape(gx.shape)

        ax.plot_surface(gx, gy, gz, cmap="viridis", alpha=0.35, linewidth=0)

    ax.set_xlabel("Size")
    ax.set_ylabel("Iteration")
    ax.set_zlabel("Seconds")
    ax.set_title(f"Points: {len(points)} | CSV files: {files_count}")
    ax.legend(loc="upper left")


def draw_equation_footer(fig, equation_text: str | None) -> None:
    if not equation_text:
        return

    wrapped_equation = textwrap.fill(
        equation_text,
        width=100,
        break_long_words=False,
        break_on_hyphens=False,
    )

    footer_text = fig.text(
        0.02,
        0.02,
        wrapped_equation,
        va="bottom",
        ha="left",
        fontsize=12,
        family="monospace",
        bbox={"facecolor": "white", "alpha": 0.9, "edgecolor": "#cccccc"},
    )
    fig._equation_footer = footer_text


def iteration_values_for_line(points: np.ndarray) -> np.ndarray:
    y = points[:, 1]
    y_min = float(np.min(y))
    y_max = float(np.max(y))

    if abs(y_max - y_min) < 1e-12:
        return np.array([y_min], dtype=float)

    # If iterations look integer-like and range is reasonable, use every integer iteration.
    y_min_i = int(math.floor(y_min))
    y_max_i = int(math.ceil(y_max))
    looks_integer = np.all(np.abs(y - np.round(y)) < 1e-9)
    if looks_integer and (y_max_i - y_min_i) <= 5000:
        return np.arange(y_min_i, y_max_i + 1, dtype=float)

    # Otherwise sample a dense continuous line.
    return np.linspace(y_min, y_max, 300)


def attach_size_line_input(
    fig,
    ax,
    points: np.ndarray,
    model: FeatureModel | None,
) -> None:
    if model is None or points.shape[0] == 0:
        return

    fig.subplots_adjust(bottom=0.38)

    input_ax = fig.add_axes([0.35, 0.15, 0.3, 0.08])
    input_ax.set_facecolor("#f5f5f5")
    text_box = TextBox(input_ax, "Size", initial=f"{float(np.mean(points[:, 0])):.6g}")

    base_x = points[:, 0]
    base_y = points[:, 1]
    base_z = points[:, 2]
    iter_values = iteration_values_for_line(points)
    line_state: dict[str, Any] = {"line": None}

    def padded_limits(values: np.ndarray, fallback_pad: float = 1.0) -> tuple[float, float]:
        vmin = float(np.min(values))
        vmax = float(np.max(values))
        span = vmax - vmin
        if span <= 1e-12:
            return vmin - fallback_pad, vmax + fallback_pad
        pad = max(0.06 * span, 1e-9)
        return vmin - pad, vmax + pad

    def draw_size_line(size_value: float) -> None:
        x_line = np.full(iter_values.shape, size_value, dtype=float)
        z_line = model.predict(x_line, iter_values)

        old_line = line_state["line"]
        if old_line is not None:
            old_line.remove()

        (line_handle,) = ax.plot(
            x_line,
            iter_values,
            z_line,
            c="crimson",
            lw=2.5,
            label=f"Predicted line (Size={size_value:.4g})",
        )
        line_state["line"] = line_handle

        handles, labels = ax.get_legend_handles_labels()
        dedup: dict[str, Any] = {}
        for h, lbl in zip(handles, labels):
            dedup[lbl] = h
        ax.legend(dedup.values(), dedup.keys(), loc="upper left")

        # Recompute full limits every time so the view can both zoom out and zoom in.
        x_all = np.concatenate([base_x, x_line])
        y_all = np.concatenate([base_y, iter_values])
        z_all = np.concatenate([base_z, z_line])

        x0, x1 = padded_limits(x_all)
        y0, y1 = padded_limits(y_all)
        z0, z1 = padded_limits(z_all)
        ax.set_xlim(x0, x1)
        ax.set_ylim(y0, y1)
        ax.set_zlim(z0, z1)

        fig.canvas.draw_idle()

    def on_submit(text: str) -> None:
        try:
            size_value = float(text.strip())
        except ValueError:
            print(f"Invalid Size value: {text!r}")
            return
        draw_size_line(size_value)

    def on_change(text: str) -> None:
        # Live update while typing when value is valid.
        try:
            size_value = float(text.strip())
        except ValueError:
            return
        draw_size_line(size_value)

    text_box.on_submit(on_submit)
    text_box.on_text_change(on_change)

    # Keep references alive; otherwise the widget can become non-interactive.
    fig._size_input_ax = input_ax
    fig._size_text_box = text_box
    fig._size_line_state = line_state

    # Draw initial line from the default value.
    on_submit(text_box.text)


def run(args: argparse.Namespace) -> None:
    input_path = Path(args.input_path).expanduser().resolve()
    files = resolve_input_csv_files(input_path, args.pattern, args.recursive)
    points = load_all_points(files)
    exp_bases = [float(s.strip()) for s in args.exp_bases.split(",") if s.strip()]

    fig = plt.figure(figsize=(10, 7))
    ax = fig.add_subplot(111, projection="3d")

    model: FeatureModel | None = None
    equation_text: str | None = None
    if len(points) > 0:
        x, y, z = points[:, 0], points[:, 1], points[:, 2]
        model = fit_feature_model(
            x,
            y,
            z,
            degree=max(1, args.degree),
            exp_bases=exp_bases,
            ridge_alpha=max(0.0, args.ridge),
        )
        equation_text = model.equation()
        z_hat = model.predict(x, y)
        score = r2_score(z, z_hat)

        print(f"Points: {len(points)} from {len(files)} CSV file(s)")
        print(f"Max polynomial degree: {max(1, args.degree)}")
        print(f"Exponential bases for n^x terms: {exp_bases}")
        print(equation_text)
        print(f"R^2 on loaded points: {score:.6f}")

        if args.query is not None:
            qx, qy = args.query
            qz = float(model.predict(np.array([qx]), np.array([qy]))[0])
            print(f"Prediction at (Size={qx}, Iteration={qy}) -> Seconds={qz:.6f}")
    else:
        print("No valid numeric points found in CSV files.")

    update_plot(
        ax,
        points,
        model,
        len(files),
        show_surface=not args.no_surface,
    )
    attach_size_line_input(fig, ax, points, model)
    draw_equation_footer(fig, equation_text)
    plt.show()


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="3D CSV plotter and feature-based z=f(x,y) fitter"
    )
    p.add_argument(
        "input_path",
        help="Path to a CSV file or a folder containing CSV files",
    )
    p.add_argument(
        "--pattern",
        default="*.csv",
        help="Glob pattern for files (default: *.csv)",
    )
    p.add_argument(
        "--recursive",
        action="store_true",
        help="Search recursively in subfolders",
    )
    p.add_argument(
        "--degree",
        type=int,
        default=2,
        help="Max polynomial degree for Size^n and Iteration^n terms (default: 2)",
    )
    p.add_argument(
        "--exp-bases",
        type=str,
        default="2,10",
        help="Comma-separated bases for n^Size and n^Iteration terms (default: 2,10)",
    )
    p.add_argument(
        "--ridge",
        type=float,
        default=1e-6,
        help="Ridge regularization strength for stable fitting (default: 1e-6)",
    )
    p.add_argument(
        "--no-surface",
        action="store_true",
        help="Plot points only (disable predicted surface)",
    )
    p.add_argument(
        "--query",
        nargs=2,
        type=float,
        metavar=("SIZE", "ITERATION"),
        help="Optional point to predict Seconds, e.g. --query 1.5 2.0",
    )
    return p


if __name__ == "__main__":
    parser = build_arg_parser()
    args = parser.parse_args()
    run(args)
