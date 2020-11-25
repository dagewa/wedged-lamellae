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
            space_group=m.space_group(),
                unit_cell=m.crystals()[0].unit_cell()
            ),
        indices=intensity.indices,
        )
    return miller.array(hkl_set, intensity.data)

if __name__ == "__main__":

    if len(sys.argv) == 5:
        column=sys.argv[4]
    else:
        column="IMEAN"

    I1 = mtz_to_miller_array(sys.argv[1], column)
    I2 = mtz_to_miller_array(sys.argv[2], column)
    title = sys.argv[3]

    I1, I2 = I1.common_sets(I2, assert_is_similar_symmetry=False)

    # For datasets of the same size, a q-q plot is just the scatter plot
    # of sorted values in dataset 1 vs sorted values in dataset 2. The
    # intensities of the datasets are low due to the low Lorentz factor
    # values, because of ED geometry.

    # Quantile-quantile plot
    x = np.sort(I1.data().as_numpy_array())
    y = np.sort(I2.data().as_numpy_array())

    print("Five number summary")
    print("I1: {:.2f} {:.2f} {:.2f} {:.2f} {:.2f}".format(*five_number_summary(x)))
    print("I2: {:.2f} {:.2f} {:.2f} {:.2f} {:.2f}".format(*five_number_summary(y)))
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
    ax.set_aspect('equal')

    # Just look at range -150, 300
    #ax.set_ylim(-150, 300)
    #ax.set_xlim(-150, 300)
    #ax.set_aspect('equal')

    # Draw y=0 and x=0 lines
    ax.axhline(alpha=0.75, zorder=0)
    ax.axvline(alpha=0.75, zorder=0)

    # Draw y=x line
    lims = [
        np.min([ax.get_xlim(), ax.get_ylim()]),  # min of both axes
        np.max([ax.get_xlim(), ax.get_ylim()]),  # max of both axes
    ]
    ax.plot(lims, lims, 'k-', alpha=0.75, zorder=0)
    ax.set_title(title)

    plt.savefig(title + ".pdf")
    plt.close()
