#!/bin/bash
set -e

# Check script input
if [ "$#" -ne 1 ]; then
    echo "You must supply the location of the data directory (nt21004-140/) only"
    exit 1
fi

# Set up directories
PROCDIR=$(pwd)
SCRIPTDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
DATAROOT=$(realpath "$1")
if [ ! -d "$DATAROOT" ]; then
    echo "$DATAROOT is not found"
    exit 1
fi

# Write a common mask definition at the top level of processing
cat > mask.phil <<+
untrusted {
  polygon = 2 958 3 1094 932 1088 998 1121 1051 1133 1135 1128 1185 1115 1226 \
            1087 1438 1021 1438 1002 1225 942 1186 917 1144 903 1075 898 1005 \
            905 962 926 945 935 929 939 923 947 4 959 2 958
}
+

# Integrate a single dataset
integrate () {
    DATADIR=$1
    NAME=$2
    BEAM_CENTRE=$3
    PEDESTAL=$4
    SIGMA_B=$5
    SIGMA_M=$6

    echo "Integrating" "$NAME"
    mkdir -p "$PROCDIR"/"$NAME"
    cd "$PROCDIR"/"$NAME"

    mkdir -p renamed-images
    cd renamed-images
    i=1
    for file in $(ls "$DATADIR"/*.mrc)
    do
        ln -sf "$file" $(printf "image_%03d.mrc" $i)
        i=$((i+1))
    done
    cd ..

    dials.generate_mask renamed-images/image_001.mrc "$PROCDIR"/mask.phil > /dev/null
    dials.import template=renamed-images/image_###.mrc \
      geometry.scan.oscillation=0,0.5\
      slow_fast_beam_centre="$BEAM_CENTRE"\
      panel.pedestal="$PEDESTAL"\
      mask=pixels.mask > /dev/null
    dials.find_spots imported.expt d_min=1.95 nproc=4 > /dev/null
    dials.index imported.expt strong.refl detector.fix=distance\
      space_group=P43212 unit_cell=68,68,109,90,90,90\
      indexing.method=real_space_grid_search > /dev/null
    dials.refine indexed.expt indexed.refl detector.fix=distance > /dev/null
    dials.plot_scan_varying_model refined.expt > /dev/null
    dials.integrate refined.expt refined.refl\
       prediction.d_min=1.95 nproc=4\
       sigma_b="$SIGMA_B" sigma_m="$SIGMA_M" > /dev/null

    # Export MTZ (for pointless / aimless scaling)
    dials.export integrated.expt integrated.refl

    # Export unscaled but merged MTZ (for qq-plot)
    aimless \
        hklin integrated.mtz hklout unscaled_merged.mtz > onlymerge.log <<+
onlymerge
+

    cd "$PROCDIR"
}

dials_scale () {
    # Scale datasets for one lamella together, then split them to produce
    # merged MTZs
    DIR=$1
    PREFIX=$2
    HIRES=$3

    echo "Scaling for $PREFIX with dials.scale"
    cd $PROCDIR
    mkdir -p $DIR
    cd $DIR
    dials.scale\
        $PROCDIR/"${PREFIX}thick"/integrated.expt $PROCDIR/"${PREFIX}thick"/integrated.refl\
        $PROCDIR/"${PREFIX}mid"/integrated.expt $PROCDIR/"${PREFIX}mid"/integrated.refl\
        $PROCDIR/"${PREFIX}thin"/integrated.expt $PROCDIR/"${PREFIX}thin"/integrated.refl\
        exclude_images=0:75:81 exclude_images=1:75:81 exclude_images=2:75:81\
        d_min=$HIRES\
        error_model=None > /dev/null
    dials.split_experiments scaled.expt scaled.refl
    dials.merge split_0.expt split_0.refl output.mtz="${PREFIX}thick.mtz"
    dials.merge split_1.expt split_1.refl output.mtz="${PREFIX}mid.mtz"
    dials.merge split_2.expt split_2.refl output.mtz="${PREFIX}thin.mtz"

    # Truncate to get Fs for refinement
    ctruncate -hklin "${PREFIX}thick.mtz" -hklout thick.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_thick.log
    ctruncate -hklin "${PREFIX}mid.mtz" -hklout mid.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_mid.log
    ctruncate -hklin "${PREFIX}thin.mtz" -hklout thin.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_thin.log

    cd $PROCDIR

}

aimless_scale () {
    # Scale datasets for one lamella together, then also merge just the
    # individual thicknesses
    DIR=$1
    PREFIX=$2
    HIRES=$3

    echo "Scaling for $PREFIX with Aimless"
    cd $PROCDIR
    mkdir -p $DIR
    cd $DIR

    # Pointless makes a mess of combining the files for lamella_2. Use rebatch
    # first to ensure we get 3 runs
    rebatch hklin "$PROCDIR/${PREFIX}mid"/integrated.mtz \
        hklout mid.mtz >/dev/null <<+
batch add 1000
+

    rebatch hklin "$PROCDIR/${PREFIX}mid"/integrated.mtz \
        hklout thin.mtz >/dev/null <<+
batch add 2000
+

    pointless\
        hklin "$PROCDIR/${PREFIX}thick"/integrated.mtz\
        hklin mid.mtz\
        hklin thin.mtz\
        hklout sorted.mtz > pointless.log <<+
ALLOW OUTOFSEQUENCEFILES
COPY
TOLERANCE 5
RUN BYFILE
+

    rm mid.mtz thin.mtz

    # Everything together
    aimless\
        hklin sorted.mtz hklout scaled.mtz > aimless.log <<+
resolution $HIRES
exclude batches 75 to 81
exclude batches 1075 to 1081
exclude batches 2075 to 2081
output unmerged
+

    # Just merge the reflections from the thick part of the crystal
    aimless\
        hklin scaled_unmerged.mtz hklout "${PREFIX}"thick.mtz > /dev/null <<+
exclude batches 75 to 3000
onlymerge
+

    # Just merge the reflections from the mid part of the crystal
    aimless\
        hklin scaled_unmerged.mtz hklout "${PREFIX}"mid.mtz > /dev/null <<+
exclude batches 1 to 100
exclude batches 2000 to 3000
onlymerge
+

    # Just merge the reflections from the thin part of the crystal
    aimless\
        hklin scaled_unmerged.mtz hklout "${PREFIX}"thin.mtz > /dev/null <<+
exclude batches 1 to 1100
onlymerge
+

    # Truncate to get Fs for refinement
    ctruncate -hklin "${PREFIX}thick.mtz" -hklout thick.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_thick.log
    ctruncate -hklin "${PREFIX}mid.mtz" -hklout mid.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_mid.log
    ctruncate -hklin "${PREFIX}thin.mtz" -hklout thin.mtz \
        -colin '/*/*/[IMEAN,SIGIMEAN]' > ctruncate_thin.log

    cd $PROCDIR
}

# Refine the model 6zeu.cif against thick, mid and thin datasets for one lamella
# then produce Fo vs Fc plots.
refine () {
    SCALEDIR=$1

    echo "Refining datasets in $SCALEDIR"
    mkdir -p "$PROCDIR"/"$SCALEDIR"_refine
    cd "$PROCDIR"/"$SCALEDIR"_refine

    for name in thick mid thin
    do
        echo "$name"
        refmac5 xyzin "$SCRIPTDIR"/6zeu.cif xyzout refmac-"$name".pdb\
            hklin "$PROCDIR"/"$SCALEDIR"/"$name".mtz\
            hklout refmac-"$name".mtz > refmac-"$name".log <<+
NCYC 10
SOURCE ELECTRON MB
LABIN FP=F SIGFP=SIGF
+
    dials.plot_Fo_vs_Fc hklin=refmac-"$name".mtz
    done

    cd "$PROCDIR"
}

###################
# DATA PROCESSING #
###################

# Integrate with pedestal of -100. I tried various pedestal levels using
# the lamella_3 datasets and found that this maximised the outer shell CC1/2.
# The assignment of datasets for thin, mid and thick come from assumption made
# using the crystal images in supervisor_evb_nt23169-1/nt21004-140/saved_images

# lamella1
integrate "$DATAROOT"/lamella_1_tilt_1/Images-Disc1/2019-04-24-155637.255\
    lamella_1_thick "1017,1080" -100 0.0025 0.2
integrate "$DATAROOT"/lamella_1_tilt_2/Images-Disc1/2019-04-24-160547.199\
    lamella_1_mid "1014,1082" -100 0.0025 0.2
integrate "$DATAROOT"/lamella_1_tilt_3/Images-Disc1/2019-04-24-161139.085\
    lamella_1_thin "1012,1080" -100 0.0025 0.2

# lamella2
integrate "$DATAROOT"/lamella_2_tilt_1/Images-Disc1/2019-04-24-141357.568\
    lamella_2_thin "1013,1033" -100 0.002 0.37
integrate "$DATAROOT"/lamella_2_tilt_2/Images-Disc1/2019-04-24-142502.849\
    lamella_2_mid "1016,1037" -100 0.002 0.37
integrate "$DATAROOT"/lamella_2_tilt_3/Images-Disc1/2019-04-24-144238.540\
    lamella_2_thick "1020,1090" -100 0.002 0.37

# lamella3
integrate "$DATAROOT"/lamella_3_tilt_1/Images-Disc1/2019-04-24-150408.105\
    lamella_3_thick "1012,1084" -100 0.002 0.3
integrate "$DATAROOT"/lamella_3_tilt_2/Images-Disc1/2019-04-24-153550.410\
    lamella_3_mid "1012,1084" -100 0.002 0.3
integrate "$DATAROOT"/lamella_3_tilt_3/Images-Disc1/2019-04-24-154246.731\
    lamella_3_thin "1013,1080" -100 0.002 0.3

dials_scale scale1 lamella_1_ 2.0
dials_scale scale2 lamella_2_ 2.4
dials_scale scale3 lamella_3_ 2.1

aimless_scale aimless1 lamella_1_ 2.0
aimless_scale aimless2 lamella_2_ 2.4
aimless_scale aimless3 lamella_3_ 2.1

# Refinement and Fo vs Fc plot creation
refine scale1
refine scale2
refine scale3

refine aimless1
refine aimless2
refine aimless3

# Create Q-Q plots and move Fo vs Fc plots, create PNGs
mkdir -p "$PROCDIR"/plots
cd "$PROCDIR"/plots

find "$PROCDIR"/*_refine/Fo_vs_Fc.pdf -exec mv {} "$PROCDIR"/plots/ \;

dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/lamella_1_thin/unscaled_merged.mtz\
    "$PROCDIR"/lamella_1_thick/unscaled_merged.mtz lamella1_unscaled
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/lamella_2_thin/unscaled_merged.mtz\
    "$PROCDIR"/lamella_2_thick/unscaled_merged.mtz lamella2_unscaled
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/lamella_3_thin/unscaled_merged.mtz\
    "$PROCDIR"/lamella_3_thick/unscaled_merged.mtz lamella3_unscaled

dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/scale1/lamella_1_thin.mtz\
    "$PROCDIR"/scale1/lamella_1_thick.mtz lamella1_dials
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/scale2/lamella_2_thin.mtz\
    "$PROCDIR"/scale2/lamella_2_thick.mtz lamella2_dials
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/scale3/lamella_3_thin.mtz\
    "$PROCDIR"/scale3/lamella_3_thick.mtz lamella3_dials

dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/aimless1/lamella_1_thin.mtz\
    "$PROCDIR"/aimless1/lamella_1_thick.mtz lamella1_aimless
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/aimless2/lamella_2_thin.mtz\
    "$PROCDIR"/aimless2/lamella_2_thick.mtz lamella2_aimless
dials.python "$SCRIPTDIR"/qqplot.py\
    "$PROCDIR"/aimless3/lamella_3_thin.mtz\
    "$PROCDIR"/aimless3/lamella_3_thick.mtz lamella3_aimless

# TODO make pngs for GOogle Doc

cd "$PROCDIR"
