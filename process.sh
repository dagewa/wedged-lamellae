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

########################
# FUNCTION DEFINITIONS #
########################

integrate () {
    # Integrate a single dataset
    DATADIR=$1
    NAME=$2
    BEAM_CENTRE=$3
    PEDESTAL=$4
    SIGMA_B=$5
    SIGMA_M=$6
    STRONG=$7

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
    if [ -z $STRONG ]; then
        dials.find_spots imported.expt d_min=1.95 nproc=4 > /dev/null
    else
        cp $STRONG .
    fi
    dials.index imported.expt strong.refl detector.fix=distance\
      space_group=P43212 unit_cell=68,68,109,90,90,90\
      indexing.method=real_space_grid_search > /dev/null
    dials.refine indexed.expt indexed.refl detector.fix=distance > /dev/null
    dials.plot_scan_varying_model refined.expt > /dev/null
    dials.integrate refined.expt refined.refl\
       prediction.d_min=1.95 nproc=4\
       sigma_b="$SIGMA_B" sigma_m="$SIGMA_M" > /dev/null

    # Export unscaled but merged MTZ (for qq-plot)
    dials.export integrated.expt integrated.refl > /dev/null
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

    echo "Simple scaling for $PREFIX with dials.scale"
    cd $PROCDIR
    mkdir -p $DIR
    cd $DIR
    dials.scale\
        $PROCDIR/"${PREFIX}thick"/integrated.expt $PROCDIR/"${PREFIX}thick"/integrated.refl\
        $PROCDIR/"${PREFIX}mid"/integrated.expt $PROCDIR/"${PREFIX}mid"/integrated.refl\
        $PROCDIR/"${PREFIX}thin"/integrated.expt $PROCDIR/"${PREFIX}thin"/integrated.refl\
        exclude_images=0:75:81 exclude_images=1:75:81 exclude_images=2:75:81\
        d_min=$HIRES\
        physical.decay_correction=False physical.absorption_correction=False\
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

refine () {
    # Refine the model 6zeu.cif against thick, mid and thin datasets for one
    # lamella then produce Fo vs Fc plots.
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
NCYC 30
SOURCE ELECTRON MB
LABIN FP=F SIGFP=SIGF
+
    dials.plot_Fo_vs_Fc hklin=refmac-"$name".mtz\
        plot_filename=Fo_vs_Fc-"$SCALEDIR"-"$name".pdf > Fo_vs_Fc-"$SCALEDIR"-"$name".log
    done

    cd "$PROCDIR"
}

make_plots() {

    echo "Creating plots"
    mkdir -p "$PROCDIR"/plots
    cd "$PROCDIR"/plots

    # Link previously-created Fo vs Fc plots here
    find "$PROCDIR" -name "Fo_vs_Fc-*.pdf" -exec ln -s {} "$PROCDIR"/plots/ \;

    # Link to crystal images with the correct descriptive name for clarity
    ln -s "$DATAROOT"/lamella_1_tilt_1/lamella_1_tilt_1.png lamella_1_thick.png
    ln -s "$DATAROOT"/lamella_1_tilt_2/lamella_1_tilt_2.png lamella_1_mid.png
    ln -s "$DATAROOT"/lamella_1_tilt_3/lamella_1_tilt_3.png lamella_1_thin.png

    ln -s "$DATAROOT"/lamella_2_tilt_1/lamella_2_tilt_1.png lamella_2_thin.png
    ln -s "$DATAROOT"/lamella_2_tilt_2/lamella_2_tilt_2.png lamella_2_mid.png
    ln -s "$DATAROOT"/lamella_2_tilt_3/lamella_2_tilt_3.png lamella_2_thick.png

    ln -s "$DATAROOT"/lamella_3_tilt_1/lamella_3_tilt_1.png lamella_3_thick.png
    ln -s "$DATAROOT"/lamella_3_tilt_2/lamella_3_tilt_2.png lamella_3_mid.png
    ln -s "$DATAROOT"/lamella_3_tilt_3/lamella_3_tilt_3.png lamella_3_thin.png

    # Do various tasks for each lamella
    for i in 1 2 3
    do
    # Q-Q plots
        # Unscaled - use links to give descriptive filename for the plot
        ln -s "$PROCDIR"/lamella_"$i"_thin/unscaled_merged.mtz\
            lamella"$i"_unscaled_thin.mtz
        ln -s "$PROCDIR"/lamella_"$i"_thick/unscaled_merged.mtz\
            lamella"$i"_unscaled_thick.mtz
        dials.python "$SCRIPTDIR"/qqplot.py\
            lamella"$i"_unscaled_thin.mtz lamella"$i"_unscaled_thick.mtz\
            lamella"$i"_unscaled
        rm lamella"$i"_unscaled_thin.mtz lamella"$i"_unscaled_thick.mtz

        # Scaled with dials.scale
        dials.python "$SCRIPTDIR"/qqplot.py\
            "$PROCDIR"/scale_"$i"/lamella_"$i"_thin.mtz\
            "$PROCDIR"/scale_"$i"/lamella_"$i"_thick.mtz lamella"$i"_dials


    # Create composite PNG images for a report
        convert lamella_"$i"_thick.png lamella_"$i"_mid.png lamella_"$i"_thin.png\
            +append lamella_"$i"_positions.png
        convert -density 300 lamella"$i"_dials.pdf -trim +repage dials.png
        convert -density 300 lamella"$i"_unscaled.pdf -trim +repage unscaled.png
        convert dials.png  nscaled.png +append lamella"$i"_QQ.png
        rm dials.png unscaled.png
        convert -density 300 Fo_vs_Fc-scale_"$i"-thick.pdf -trim +repage thick.png
        convert -density 300 Fo_vs_Fc-scale_"$i"-mid.pdf -trim +repage mid.png
        convert -density 300 Fo_vs_Fc-scale_"$i"-thin.pdf -trim +repage thin.png
        convert thick.png mid.png thin.png +append Fo_vs_Fc-scale_"$i".png
        rm thick.png mid.png thin.png
    done

    # Remove links we no longer need here
    rm lamella_{1,2,3}_{thick,mid,thin}.png

    cd "$PROCDIR"
}

pedestal_test() {
    ORIG_PROCDIR=$PROCDIR
    mkdir -p $PROCDIR/pedestal
    cd $PROCDIR/pedestal
    PROCDIR=$(pwd)

    cat > mask.phil <<+
untrusted {
  polygon = 2 958 3 1094 932 1088 998 1121 1051 1133 1135 1128 1185 1115 1226 \
            1087 1438 1021 1438 1002 1225 942 1186 917 1144 903 1075 898 1005 \
            905 962 926 945 935 929 939 923 947 4 959 2 958
}
+

    # Integrate pedestal -100 first to get spot-finding results to use at other
    # pedestal levels by passing in STRONG
    for PEDESTAL in -100 -10 -20 -30 -40 -50 -60 -70 -80 -90 -100 -110 -120\
        -130 -140 -150 -160 -170 -180 -190 -200 -210 -220 -230
    do
        # lamella1
        integrate "$DATAROOT"/lamella_1_tilt_1/Images-Disc1/2019-04-24-155637.255\
            lamella_1_thick_"$PEDESTAL" "1017,1080" "$PEDESTAL" 0.0025 0.2\
            $(find . -path ./lamella_1_thick_-100/strong.refl)
        integrate "$DATAROOT"/lamella_1_tilt_2/Images-Disc1/2019-04-24-160547.199\
            lamella_1_mid_"$PEDESTAL" "1014,1082" "$PEDESTAL" 0.0025 0.2\
            $(find . -path ./lamella_1_mid_-100/strong.refl)
        integrate "$DATAROOT"/lamella_1_tilt_3/Images-Disc1/2019-04-24-161139.085\
            lamella_1_thin_"$PEDESTAL" "1012,1080" "$PEDESTAL" 0.0025 0.2\
            $(find . -path ./lamella_1_thin_-100/strong.refl)
        mkdir -p scale_1_"$PEDESTAL" && cd scale_1_"$PEDESTAL"
        dials.scale\
            "$PROCDIR"/lamella_1_thick_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_1_thick_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_1_mid_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_1_mid_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_1_thin_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_1_thin_"$PEDESTAL"/integrated.refl\
            exclude_images=0:75:81 exclude_images=1:75:81 exclude_images=2:75:81\
            d_max=10 d_min=2.0 error_model=None json=scale.json > /dev/null
        cd "$PROCDIR"

        # lamella2
        integrate "$DATAROOT"/lamella_2_tilt_1/Images-Disc1/2019-04-24-141357.568\
            lamella_2_thin_"$PEDESTAL" "1013,1033" "$PEDESTAL" 0.002 0.37\
            $(find . -path ./lamella_2_thin_-100/strong.refl)
        integrate "$DATAROOT"/lamella_2_tilt_2/Images-Disc1/2019-04-24-142502.849\
            lamella_2_mid_"$PEDESTAL" "1016,1037" "$PEDESTAL" 0.002 0.37\
            $(find . -path ./lamella_2_mid_-100/strong.refl)
        integrate "$DATAROOT"/lamella_2_tilt_3/Images-Disc1/2019-04-24-144238.540\
            lamella_2_thick_"$PEDESTAL" "1020,1090" "$PEDESTAL" 0.002 0.37\
            $(find . -path ./lamella_2_thick_-100/strong.refl)
        mkdir -p scale_2_"$PEDESTAL" && cd scale_2_"$PEDESTAL"
        dials.scale\
            "$PROCDIR"/lamella_2_thick_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_2_thick_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_2_mid_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_2_mid_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_2_thin_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_2_thin_"$PEDESTAL"/integrated.refl\
            exclude_images=0:75:81 exclude_images=1:75:81 exclude_images=2:75:81\
            d_max=10 d_min=2.4 error_model=None json=scale.json > /dev/null
        cd "$PROCDIR"

        # lamella3
        integrate "$DATAROOT"/lamella_3_tilt_1/Images-Disc1/2019-04-24-150408.105\
            lamella_3_thick_"$PEDESTAL" "1012,1084" "$PEDESTAL" 0.002 0.3\
            $(find . -path ./lamella_3_thick_-100/strong.refl)
        integrate "$DATAROOT"/lamella_3_tilt_2/Images-Disc1/2019-04-24-153550.410\
            lamella_3_mid_"$PEDESTAL" "1012,1084" "$PEDESTAL" 0.002 0.3\
            $(find . -path ./lamella_3_mid_-100/strong.refl)
        integrate "$DATAROOT"/lamella_3_tilt_3/Images-Disc1/2019-04-24-154246.731\
            lamella_3_thin_"$PEDESTAL" "1013,1080" "$PEDESTAL" 0.002 0.3\
            $(find . -path ./lamella_3_thin_-100/strong.refl)
        mkdir -p scale_3_"$PEDESTAL" && cd scale_3_"$PEDESTAL"
        dials.scale\
            "$PROCDIR"/lamella_3_thick_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_3_thick_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_3_mid_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_3_mid_"$PEDESTAL"/integrated.refl\
            "$PROCDIR"/lamella_3_thin_"$PEDESTAL"/integrated.expt $PROCDIR/lamella_3_thin_"$PEDESTAL"/integrated.refl\
            exclude_images=0:75:81 exclude_images=1:75:81 exclude_images=2:75:81\
            d_max=10 d_min=2.1 error_model=None json=scale.json > /dev/null
        cd "$PROCDIR"
    done

    # Generate plots
    for i in 1 2 3
    do

        dials.python "$SCRIPTDIR"/cchalf_pedestal.py lamella_"$i" scale_"$i"_*
    done

    PROCDIR=$ORIG_PROCDIR
}

########
# MAIN #
########

# Uncomment below to investigate different pedestal levels
#pedestal_test

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

dials_scale scale_1 lamella_1_ 2.0
dials_scale scale_2 lamella_2_ 2.4
dials_scale scale_3 lamella_3_ 2.1

# Refinement
refine scale_1
refine scale_2
refine scale_3

# Plot creation
make_plots
