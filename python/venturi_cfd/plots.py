"""Publication-style figures: mirrored contour fields, axis profiles, losses.

Reproduces the visual layout of the MATLAB scripts — the axisymmetric
half-domain is mirrored about the axis r = 0 so the full tube is shown.
"""

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np


def _mirror(zc, rc, field):
    """Mirror a (Nz, Nr) half-domain field about the axis r = 0.

    Returns (Z, R, F) transposed to (2*Nr, Nz) for matplotlib.
    """
    rfull = np.concatenate([-rc[::-1], rc])
    F = np.concatenate([field[:, ::-1], field], axis=1)      # (Nz, 2Nr)
    return zc, rfull, F.T


def plot_velocity_field(res, filename, title):
    """|U| contours + streamlines over the mirrored tube."""
    zc, rc, Rw = res.zc, res.rc, res.Rw
    z, rfull, Um = _mirror(zc, rc, res.Umag)
    _, _, Uz = _mirror(zc, rc, res.uc)
    Ur = np.concatenate([-res.vc[:, ::-1], res.vc], axis=1).T

    fig, ax = plt.subplots(figsize=(11.8, 3.8), facecolor="w")
    cf = ax.contourf(z, rfull, Um, levels=26, cmap="jet")
    cb = fig.colorbar(cf, ax=ax)
    cb.set_label("|U| [m/s]")
    sy = np.linspace(-0.9 * res.geom.R1, 0.9 * res.geom.R1, 16)
    start = np.column_stack([np.full_like(sy, z[0]), sy])
    ax.streamplot(z, rfull, np.nan_to_num(Uz), np.nan_to_num(Ur),
                  start_points=start, color=(0, 0, 0, 0.35),
                  linewidth=0.8, arrowsize=0.7)
    ax.plot(zc, Rw, "k", lw=1.2)
    ax.plot(zc, -Rw, "k", lw=1.2)
    ax.set_xlabel("z [m] (flow direction)")
    ax.set_ylabel("r [m]")
    ax.set_title(title)
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlim(z[0], z[-1])
    fig.tight_layout()
    fig.savefig(filename, dpi=150)
    plt.close(fig)


def plot_pressure_field(res, filename, title, label="p [Pa]"):
    """Pressure contours over the mirrored tube."""
    zc, rc, Rw = res.zc, res.rc, res.Rw
    pp = np.where(res.fluid, res.p, np.nan)
    z, rfull, Pm = _mirror(zc, rc, pp)

    fig, ax = plt.subplots(figsize=(11.8, 3.8), facecolor="w")
    cf = ax.contourf(z, rfull, Pm, levels=26, cmap="jet")
    cb = fig.colorbar(cf, ax=ax)
    cb.set_label(label)
    ax.plot(zc, Rw, "k", lw=1.2)
    ax.plot(zc, -Rw, "k", lw=1.2)
    ax.set_xlabel("z [m]")
    ax.set_ylabel("r [m]")
    ax.set_title(title)
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlim(z[0], z[-1])
    fig.tight_layout()
    fig.savefig(filename, dpi=150)
    plt.close(fig)


def plot_axis_profiles(res, filename, title):
    """Velocity magnitude and pressure along the axis (r ~ 0)."""
    zc = res.zc
    ua = res.Umag[:, 0]
    pa = np.where(res.fluid, res.p, np.nan)[:, 0]

    fig, ax1 = plt.subplots(figsize=(7.6, 4.6), facecolor="w")
    ax1.plot(zc, ua, "C0", lw=2)
    ax1.set_ylabel("|U| on the axis [m/s]", color="C0")
    ax1.tick_params(axis="y", colors="C0")
    ax2 = ax1.twinx()
    ax2.plot(zc, pa, "C1", lw=2)
    ax2.set_ylabel("Pressure on the axis [Pa]", color="C1")
    ax2.tick_params(axis="y", colors="C1")
    ax1.set_xlabel("z [m]")
    ax1.grid(True, alpha=0.4)
    for zline in (res.geom.z2, res.geom.z3):
        ax1.axvline(zline, ls="--", color="k", lw=0.8)
    ax1.set_title(title)
    fig.tight_layout()
    fig.savefig(filename, dpi=150)
    plt.close(fig)


def plot_head_loss(zc, head_mm, geom, filename, title, ylabel):
    """Head-loss curve along the venturi, in mm of water column."""
    fig, ax = plt.subplots(figsize=(7.6, 4.2), facecolor="w")
    ax.plot(zc, head_mm, lw=2)
    ax.grid(True, alpha=0.4)
    for zline in (geom.z2, geom.z3):
        ax.axvline(zline, ls="--", color="k", lw=0.8)
    ax.set_xlabel("z [m]")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(filename, dpi=150)
    plt.close(fig)
