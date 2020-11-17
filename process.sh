#!/bin/bash
set -e

cat > mask.phil <<+
untrusted {
  polygon = 2 958 3 1094 932 1088 998 1121 1051 1133 1135 1128 1185 1115 1226 \
            1087 1438 1021 1438 1002 1225 942 1186 917 1144 903 1075 898 1005 \
            905 962 926 945 935 929 939 923 947 4 959 2 958
}
+

# Set up directories
PROCDIR=$(pwd)
SCRIPTDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
DATAROOT="$SCRIPTDIR"/supervisor_evb_nt23169-1/nt21004-140

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

    # export MTZ (for pointless / aimless)
    dials.export integrated.expt integrated.refl

    # export unscaled but merged MTZ (for qq-plot)
    aimless \
        hklin integrated.mtz hklout unscaled_merged.mtz > onlymerge.log <<+
onlymerge
+

    cd "$PROCDIR"
}

# Integrate with pedestal of -100. For lamella_3 this maximises outer shell
# CC1/2. Select correct datasets for thin, mid and thick

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
    lamella_3_thin "1012,1084" -100 0.002 0.3
integrate "$DATAROOT"/lamella_3_tilt_2/Images-Disc1/2019-04-24-153550.410\
    lamella_3_mid "1012,1084" -100 0.002 0.3
integrate "$DATAROOT"/lamella_3_tilt_3/Images-Disc1/2019-04-24-154246.731\
    lamella_3_thick "1013,1080" -100 0.002 0.3


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

    cd $PROCDIR

}

aimless_scale () {
    # Scale datasets for one lamella together, then split them to produce
    # merged MTZs
    DIR=$1
    PREFIX=$2
    HIRES=$3

    echo "Scaling for $PREFIX with Aimless"
    cd $PROCDIR
    mkdir -p $DIR
    cd $DIR

    pointless\
        hklin "$PROCDIR/${PREFIX}thick"/integrated.mtz\
        hklin "$PROCDIR/${PREFIX}mid"/integrated.mtz\
        hklin "$PROCDIR/${PREFIX}thin"/integrated.mtz\
        hklout sorted.mtz > pointless.log <<+
ALLOW OUTOFSEQUENCEFILES
COPY
TOLERANCE 5
+
    aimless\
        hklin sorted.mtz hklout scaled.mtz > aimless.log <<+
resolution $HIRES
exclude batches 75 to 81
exclude batches 1075 to 1081
exclude batches 2075 to 2081
+
# TODO exclude batches and split MTZs.

    cd $PROCDIR
}

dials_scale scale1 lamella_1_ 2.0
dials_scale scale2 lamella_2_ 2.4
dials_scale scale3 lamella_3_ 2.1

aimless_scale aimless1 lamella_1_ 2.0
aimless_scale aimless2 lamella_2_ 2.4
aimless_scale aimless3 lamella_3_ 2.1

## Q-Q plots
dials.python "$SCRIPTDIR"/qqplot.py lamella_1_thin/unscaled_merged.mtz\
    lamella_1_thick/unscaled_merged.mtz lamella1_unscaled
dials.python "$SCRIPTDIR"/qqplot.py lamella_2_thin/unscaled_merged.mtz\
    lamella_2_thick/unscaled_merged.mtz lamella2_unscaled
dials.python "$SCRIPTDIR"/qqplot.py lamella_3_thin/unscaled_merged.mtz\
    lamella_3_thick/unscaled_merged.mtz lamella3_unscaled

dials.python "$SCRIPTDIR"/qqplot.py scale1/lamella_1_thin.mtz scale1/lamella_1_thick.mtz lamella1
dials.python "$SCRIPTDIR"/qqplot.py scale2/lamella_2_thin.mtz scale2/lamella_2_thick.mtz lamella2
dials.python "$SCRIPTDIR"/qqplot.py scale3/lamella_3_thin.mtz scale3/lamella_3_thick.mtz lamella3

refine () {
  # refine data against model to make Fo vs Fc plots
  echo "TO DO"
}
