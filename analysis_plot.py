#! /usr/bin/env cctbx.python
import os, sys
from iotbx import mtz
import numpy as np
import matplotlib.pyplot as plt

from cctbx import miller, crystal
from scitbx.math import five_number_summary


def mtz_to_miller_array(filename, column="IMEAN"):
    m = mtz.object(filename)
    intensity = m.extract_observations(column, "SIG" + column)

    hkl_set = miller.set(
        crystal_symmetry=crystal.symmetry(
            space_group=m.space_group(), unit_cell=m.crystals()[0].unit_cell()
        ),
        indices=intensity.indices,
    )
    return miller.array(hkl_set, intensity.data)


# Moving window average, general idea taken from
# https://stackoverflow.com/questions/47484899/moving-average-produces-array-of-different-length
def moving_average(x, N):
    padded = np.pad(
        x, (N // 2, N - 1 - N // 2), mode="constant", constant_values=(None,)
    )
    return np.convolve(padded, np.ones((N,)) / N, mode="valid")


def diffI_plot(I1, I2):
    Imean = ((I1.data() + I2.data()) / 2).as_numpy_array()
    Idiff = (I1.data() - I2.data()).as_numpy_array()
    d_min = I1.d_spacings().data().as_numpy_array()

    # Sort Idiff according by Imean for moving average calculation
    perm = Imean.argsort()
    Idiff = Idiff[perm]
    Imean = Imean[perm]

    window_width = 100
    ma = moving_average(Idiff, window_width)

    fig, ax = plt.subplots()
    ax.scatter(Imean, Idiff, alpha=0.1, edgecolors="none")
    ax.plot(Imean, ma, color="red", alpha=0.5)
    ax.set_facecolor("lightgrey")
    ax.set_xlim(-1, 15)
    ax.set_ylim(-2, 2)

    # Draw y=0 and x=0 lines
    ax.axhline(alpha=0.75, zorder=0)
    ax.axvline(alpha=0.75, zorder=0)

    plt.xlabel(r"$I$")
    plt.ylabel(r"$\Delta I$")
    ax.set_title(title)
    plt.savefig(title + "_dI.pdf")
    plt.close()


def qq_plot(I1, I2, title):

    # For datasets of the same size, a q-q plot is just the scatter plot
    # of sorted values in dataset 1 vs sorted values in dataset 2. The
    # intensities of the datasets are low due to the low Lorentz factor
    # values, because of ED geometry.

    # Quantile-quantile plot
    x = np.sort(I1.data().as_numpy_array())
    y = np.sort(I2.data().as_numpy_array())

    fig, ax = plt.subplots()
    ax.scatter(x, y)
    plt.xlabel(os.path.basename(sys.argv[1]))
    plt.ylabel(os.path.basename(sys.argv[2]))

    # Cut off strongest 5% of data, and also remove first .1% which are probably
    # outliers
    maxI = np.max([x[int(len(x) * 0.95)], y[int(len(x) * 0.95)]])
    minI = np.min([x[int(len(x) / 1000)], y[int(len(x) / 1000)]])
    ax.set_ylim(minI, maxI)
    ax.set_xlim(minI, maxI)
    ax.set_aspect("equal")

    # Just look at range -150, 300
    # ax.set_ylim(-150, 300)
    # ax.set_xlim(-150, 300)
    # ax.set_aspect('equal')

    # Draw y=0 and x=0 lines
    ax.axhline(alpha=0.75, zorder=0)
    ax.axvline(alpha=0.75, zorder=0)

    # Draw y=x line
    lims = [
        np.min([ax.get_xlim(), ax.get_ylim()]),  # min of both axes
        np.max([ax.get_xlim(), ax.get_ylim()]),  # max of both axes
    ]
    ax.plot(lims, lims, "k-", alpha=0.75, zorder=0)
    ax.set_title(title)

    plt.savefig(title + "_qq.pdf")
    plt.close()


if __name__ == "__main__":

    if len(sys.argv) == 5:
        column = sys.argv[4]
    else:
        column = "IMEAN"

    I1 = mtz_to_miller_array(sys.argv[1], column)
    I2 = mtz_to_miller_array(sys.argv[2], column)
    title = sys.argv[3]

    print(f"{sys.argv[1]} has {I1.size()} reflections")
    print(f"{sys.argv[2]} has {I2.size()} reflections")
    I1, I2 = I1.common_sets(I2, assert_is_similar_symmetry=False)
    assert (I1.indices() == I2.indices()).all_eq(True)
    print(f"{I1.size()} reflections are common")

    print("Five number summaries")
    print(
        "I1: {:.2f} {:.2f} {:.2f} {:.2f} {:.2f}".format(*five_number_summary(I1.data()))
    )
    print(
        "I2: {:.2f} {:.2f} {:.2f} {:.2f} {:.2f}".format(*five_number_summary(I2.data()))
    )

    # Plot of ΔI vs I
    diffI_plot(I1, I2)

    # Q-Q plot
    qq_plot(I1, I2, title)
