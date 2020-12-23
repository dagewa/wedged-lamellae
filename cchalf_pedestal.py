#! /usr/bin/env cctbx.python
import os, sys
import json
import numpy as np
import matplotlib.pyplot as plt
from matplotlib import cm


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Please provide a title followed by directories containing scale.json")
        sys.exit()

    title = sys.argv[1]
    dirs = sys.argv[2:]
    job_dirs = [os.path.split(os.path.abspath(e))[1] for e in dirs]
    pedestals = [float(e.split("_")[-1]) for e in job_dirs]
    pedestals, job_dirs, dirs = zip(*sorted(zip(pedestals, job_dirs, dirs)))

    plot_data = []
    for pedestal, d in zip(pedestals, dirs):
        pth = os.path.join(d, "scale.json")
        with open(pth, "r") as f:
            data = json.load(f)

        res_table = data["scaling_tables"][1]
        headings = res_table[0]
        bins = res_table[1:]
        assert headings[0] == "Resolution (Å)"
        assert headings[1] == "N(obs)"
        assert headings[-2] == "CC<sub>½</sub>"

        cc_half_bins = [e[-2] for e in bins]
        cc_half_bins = [float(e.replace("*", "")) for e in cc_half_bins]
        res_range_bins = [e[0] for e in bins]
        res_bin_centres = []
        for res_range in res_range_bins:
            low, high = res_range.split("-")
            res_bin_centres.append((float(low) + float(high) / 2))

        plot_data.append(
            {
                "pedestal": pedestal,
                "n_obs": [int(e[1]) for e in bins],
                "res range": res_range_bins,
                "res mid": res_bin_centres,
                "CC1/2": cc_half_bins,
            }
        )

    # CC1/2 in resolution bins spaghetti plot is difficult to interpret
    fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=[14.4, 4.8])
    colors = [cm.cool(x) for x in np.linspace(0, 1, len(plot_data))]
    for line_color, pd in zip(colors, plot_data):
        # plot resolution as 1/d^2
        inv_dsq = [1.0 / d ** 2 for d in pd["res mid"]]
        ax1.plot(inv_dsq, pd["CC1/2"], color=line_color)
    ax1.set_title(r"$CC_{1/2}$")
    ax1.set_xlabel(r"$1/d^2$")

    # So, inspired by https://journals.iucr.org/j/issues/2016/03/00/zw5005/#SEC2.3,
    # calculate an overall CC1/2 using the weighted average across the bins
    pedestals = [e["pedestal"] for e in plot_data]
    av_cchalf = []
    for pd in plot_data:
        wght_sum = sum([n * cc for n, cc in zip(pd["n_obs"], pd["CC1/2"])])
        total_n_obs = sum(pd["n_obs"])
        av_cchalf.append(wght_sum / total_n_obs)
    ax2.scatter(pedestals, av_cchalf, c=colors)
    ax2.set_xlabel("Pedestal")
    ax2.set_title(r"Average $CC_{1/2}$")

    # The overall CC1/2 generally looks worse as the pedestal gets more negative
    # (which means *adding* more counts to the raw images). However, more
    # reflections are processed in these cases. It is not obvious why yet
    total_n_obs = [sum(pd["n_obs"]) for pd in plot_data]
    pedestals, total_n_obs = zip(*sorted(zip(pedestals, total_n_obs)))
    ax3.plot(pedestals, total_n_obs)
    ax3.set_xlabel("Pedestal")
    ax3.set_title(r"$N_{obs}$")

    fig.suptitle(title)

    plt.savefig(title + ".pdf")
    plt.close()
