#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    (repo forall -c "git reset --hard") >/dev/null
    cleanup
    echo $1
    exit 1
  fi
}

  rm -f .repo/local_manifests/device.xml
  rm -f .repo/local_manifests/dyn-*.xml
  rm -f .repo/local_manifests/roomservice.xml
  if [ -f $WORKSPACE/build_env/cleanup.sh ]
  then
    bash $WORKSPACE/build_env/cleanup.sh
  fi

function cleanup {
  rm -f .repo/local_manifests/device.xml
  rm -f .repo/local_manifests/dyn-*.xml
  rm -f .repo/local_manifests/roomservice.xml
  if [ -f $WORKSPACE/build_env/cleanup.sh ]
  then
    bash $WORKSPACE/build_env/cleanup.sh
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN" ]
then
  echo CLEAN not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ ! -z "$GERRIT_CHANGES" ]
	then
	echo $GERRIT_CHANGES > workfile.txt
	export GERRITDEVICE=`grep 'cyandream-devices/android_device' workfile.txt`
	rm -f workfile.txt
fi

if [ -z "$DEVICE" ]
then
	if [ ! -z "$GERRIT_CHANGE_ID" ]
		then
  	  if [ "$GERRIT_PROJECT" = "$GERRITDEVICE" ]
	  	then
	  	echo $GERRITDEVICE > workfile.txt
	  	if [ "$GERRITDEVICE" = "cyandream-devices/android_device_samsung_tuna" ]
			  then
		  	export DEVICE=maguro
  	  	elif [ "$GERRITDEVICE" =~ "cyandream-devices/android_device_samsung" ]
			then
		  	export DEVICE=`grep 'cyandream-devices/android_device_samsung_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "cyandream-devices/android_device_lge" ]
		  	then
		  	export DEVICE=`grep 'cyandream-devices/android_device_lge_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "cyandream-devices/android_device_htc" ]
		  	then
		  	export DEVICE=`grep 'cyandream-devices/android_device_htc_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "cyandream-devices/android_device_sony" ]
		  	then
		  	export DEVICE=`grep 'cyandream-devices/android_device_sony_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "cyandream-devices/android_device_motorola" ]
		  	then
		  	export DEVICE=`grep 'cyandream-devices/android_device_motorola_' workfile.txt`
	  	else
		  	echo compiling gerrit changes for $GERRITDEVICE not supported yet, stopping.
	      	rm -f workfile.txt
		  	exit 1
	  	fi
	  	rm -f workfile.txt
	  	unset GERRITDEVICE
	else
		export DEVICE=mako
  	  fi
  else
      echo DEVICE not specified
      exit 1
	fi
fi

if [ -z "$RELEASE_TYPE" ]
then
  echo RELEASE_TYPE not specified
  exit 1
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=http
fi
export LUNCH=cd_$DEVICE-userdebug

export PYTHONDONTWRITEBYTECODE=1

# colorization fix in Jenkins
export CL_RED="\"\033[31m\""
export CL_GRN="\"\033[32m\""
export CL_YLW="\"\033[33m\""
export CL_BLU="\"\033[34m\""
export CL_MAG="\"\033[35m\""
export CL_CYN="\"\033[36m\""
export CL_RST="\"\033[0m\""

cd $WORKSPACE
rm -rf archive
mkdir -p archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export PATH=~/bin:$PATH

export USE_CCACHE=1
export CCACHE_NLEVELS=4
export BUILD_WITH_COLORS=0

# remove device-specific stuff
rm -f .repo/local_manifests/device.xml
rm -f .repo/local_manifests/roomservice.xml


platform=`uname -s`
if [ "$platform" = "Darwin" ]
then
  export BUILD_MAC_SDK_EXPERIMENTAL=1
  # creating a symlink...
  rm -rf /Volumes/android/tools/hudson.model.JDK/Ubuntu
  ln -s /Library/Java/JavaVirtualMachines/jdk1.7.0_25.jdk/Contents/Home /Volumes/android/tools/hudson.model.JDK/Ubuntu
fi

REPO=$(which repo)
if [ -z "$REPO" ]
then
  mkdir -p ~/bin
  curl http://commondatastorage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

if [ "$REPO_BRANCH" = "cd-4.4" ]
then
   JENKINS_BUILD_DIR=kitkat
elif [ "$REPO_BRANCH" = "cd-4.3" ]
then
   JENKINS_BUILD_DIR=jellybean
else
   JENKINS_BUILD_DIR=$REPO_BRANCH
fi

export JENKINS_BUILD_DIR

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ "$STABILIZATION_BRANCH" = "true" ]
then
  SYNC_BRANCH="stable/$REPO_BRANCH"
  # Temporary: Let the stab builds fallback to the mainline dependency 
  export ROOMSERVICE_BRANCHES="$REPO_BRANCH"
else
  SYNC_BRANCH=$REPO_BRANCH
fi

if [ ! -z "$RELEASE_MANIFEST" ]
then
  MANIFEST="-m $RELEASE_MANIFEST"
else
  RELEASE_MANIFEST=""
  MANIFEST=""
fi

rm -rf .repo/manifests*
rm -f .repo/local_manifests/dyn-*.xml
repo init -u $SYNC_PROTO://github.com/CyanDreamProject/android.git -b $SYNC_BRANCH $MANIFEST
check_result "repo init failed."

echo "get proprietary stuff..."
if [ ! -d vendor/cd-priv ]
then
  git clone git@bitbucket.org:cyandreamproject/android_vendor_cd-priv.git -b $SYNC_BRANCH vendor/cd-priv
fi

cd vendor/cd-priv
## Get rid of possible local changes
git reset --hard
git pull -s resolve
cd ../..
bash vendor/cd-priv/setup

# make sure ccache is in PATH
if [ "$platform" = "Darwin" ]
then
export PATH="$PATH:/usr/local/bin/:$PWD/prebuilts/misc/darwin-x86/ccache"
else
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/$(uname|awk '{print tolower($0)}')-x86/ccache"
fi
export CCACHE_DIR=~/.ccache

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

mkdir -p .repo/local_manifests
rm -f .repo/local_manifest.xml
rm -f .repo/local_manifests/twrp.xml
rm -f .repo/local_manifests/device.xml

rm -rf $WORKSPACE/local_manifests

if [ "$TWRP" = "true" ]
then
  cp $WORKSPACE/local_manifests/twrp_manifest.xml .repo/local_manifests/twrp.xml
fi

check_result "Bootstrap failed"

echo Core Manifest:
cat .repo/manifest.xml

## TEMPORARY: Some kernels are building _into_ the source tree and messing
## up posterior syncs due to changes
rm -rf kernel/*
# delete symlink for vendor before sync
rm -rf vendor/cm

echo Syncing...
repo sync -d -c > /dev/null
check_result "repo sync failed."
if [ -z "$GERRIT_CHANGE_NUMBER" ]
then
  echo ""
else
  export GERRIT_XLATION_LINT=true
  export GERRIT_CHANGES=$GERRIT_CHANGE_NUMBER
  if [ "$GERRIT_PATCHSET_NUMBER" = "1" ]
  then
    export CD_EXTRAVERSION=gerrit-$GERRIT_CHANGE_NUMBER
  else
    export CD_EXTRAVERSION=gerrit-$GERRIT_CHANGE_NUMBER.$GERRIT_PATCHSET_NUMBER
  fi
fi
echo Sync complete.

# workaround for devices that are not 100% supported by CyanDream
echo creating symlink...
ln -s cyandream vendor/cm

. build/envsetup.sh
# Workaround for failing translation checks in common hardware repositories
if [ ! -z "$GERRIT_XLATION_LINT" ]
then
    LUNCH=$(echo $LUNCH@$DEVICEVENDOR | sed -f $WORKSPACE/hudson/shared-repo.map)
fi

lunch $LUNCH
check_result "lunch failed."

# save manifest used for build (saving revisions as current HEAD)

# include only the auto-generated locals
#TEMPSTASH=$(mktemp -d)
#mv .repo/local_manifests/* $TEMPSTASH
#mv $TEMPSTASH/roomservice.xml .repo/local_manifests/

# save it
repo manifest -o $WORKSPACE/archive/manifest.xml -r

# restore all local manifests
#mv $TEMPSTASH/* .repo/local_manifests/ 2>/dev/null
#rmdir $TEMPSTASH

rm -f $OUT/system/build.prop
rm -f $OUT/CyanDream-*.zip*

UNAME=$(uname)

if [ ! -z "$BUILD_USER_ID" ]
then
  export RELEASE_TYPE=CD_EXPERIMENTAL
fi

export SIGN_BUILD=false

if [ "$RELEASE_TYPE" = "CD_NIGHTLY" ]
then
  if [ -z "$GERRIT_CHANGE_NUMBER" ]
  then
    export CD_NIGHTLY=true
  else
    export CD_EXPERIMENTAL=true
  fi
elif [ "$RELEASE_TYPE" = "CD_RELEASE" ]
then
  export CD_RELEASE=true
  if [ "$SIGNED" = "true" ]
  then
    SIGN_BUILD=true
  fi
elif [ "$RELEASE_TYPE" = "CD_SNAPSHOT" ]
then
  export CD_SNAPSHOT=true
  if [ "$SIGNED" = "true" ]
  then
    SIGN_BUILD=true
  fi
fi

if [ ! -z "$CD_EXTRAVERSION" ]
then
  export CD_EXPERIMENTAL=true
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export CD_EXPERIMENTAL=true
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/hudson/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/hudson/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
  if [ ! -z "$GERRIT_XLATION_LINT" ]
  then
    python $WORKSPACE/hudson/xlationlint.py $GERRIT_CHANGES
    check_result "basic XML lint failed."
  fi
fi

if [ "$CLEAN" = "true" ]
then
  rm -rf out
fi

export machine=`uname -n`
if [ ! "$machine" = "yannik-MacBookPro" ]
then
	if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "20.0" ]
	then
	  ccache -M 20G
	fi
else
	rm -rf /home/yannik/.ccache
	if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "5.0" ]
	then
	  ccache -M 5G
	fi
fi

WORKSPACE=$WORKSPACE LUNCH=$LUNCH bash $WORKSPACE/hudson/changes/buildlog.sh 2>&1

time mka bacon recoveryzip recoveryimage

check_result "Build failed."

if [ "$SIGN_BUILD" = "true" ]
then
  MODVERSION=$(cat $OUT/system/build.prop | grep ro.cm.version | cut -d = -f 2)
  if [ ! -z "$MODVERSION" -a -f $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip ]
  then
    if [ -s $OUT/ota_script_path ]
    then
        OTASCRIPT=$(cat $OUT/ota_script_path)
    else
        OTASCRIPT=./build/tools/releasetools/ota_from_target_files
    fi
    ./build/tools/releasetools/sign_target_files_apks -e Term.apk= -d vendor/cd-priv/keys $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip $OUT/$MODVERSION-signed-intermediate.zip
    $OTASCRIPT -k vendor/cd-priv/keys/releasekey $OUT/$MODVERSION-signed-intermediate.zip $WORKSPACE/archive/CyanDream-$MODVERSION-signed.zip
    if [ "$FASTBOOT_IMAGES" = "true" ]
    then
       ./build/tools/releasetools/img_from_target_files $OUT/$MODVERSION-signed-intermediate.zip $WORKSPACE/archive/CyanDream-$MODVERSION-fastboot.zip
    fi
    rm -f $OUT/ota_script_path
  else
    echo "Unable to find target files to sign"
    exit 1
  fi
else
  for f in $(ls $OUT/CyanDream-*.zip*)
  do
    ln $f $WORKSPACE/archive/$(basename $f)
  done
fi
if [ -f $OUT/utilties/update.zip ]
then
  cp $OUT/utilties/update.zip $WORKSPACE/archive/recovery.zip
fi
if [ -f $OUT/recovery.img ]
then
  cp $OUT/recovery.img $WORKSPACE/archive
fi

# archive the build.prop as well
ZIP=$(ls $WORKSPACE/archive/CyanDream-*.zip | grep -v -- -fastboot)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

if [ "$TARGET_BUILD_VARIANT" = "user" -a "$EXTRA_DEBUGGABLE_BOOT" = "true" ]
then
  # Minimal rebuild to get a debuggable boot image, just in case
  rm -f $OUT/root/default.prop
  DEBLUNCH=$(echo $LUNCH|sed -e 's|-user$|-userdebug|g')
  breakfast $DEBLUNCH
  mka bootimage
  check_result "Failed to generate a debuggable bootimage"
  cp $OUT/boot.img $WORKSPACE/archive/boot-debuggable.img
fi

# Build is done, cleanup the environment
cleanup

# CORE: save manifest used for build (saving revisions as current HEAD)

# Stash away other possible manifests
#TEMPSTASH=$(mktemp -d)
#mv .repo/local_manifests $TEMPSTASH

repo manifest -o $WORKSPACE/archive/core.xml -r

#mv $TEMPSTASH/local_manifests .repo
#rmdir $TEMPSTASH

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive

echo "release new build..."
bash vendor/cd-priv/release/release $RELEASE_TYPE
