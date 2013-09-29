#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    (repo forall -c "git reset --hard") >/dev/null
    rm -f .repo/local_manifests/dyn-*.xml
    rm -f .repo/local_manifests/roomservice.xml
    echo $1
    exit 1
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
	export GERRITDEVICE=`grep 'CyanDreamProject/android_device' workfile.txt`
	rm -f workfile.txt
fi

if [ -z "$DEVICE" ]
then
	if [ ! -z "$GERRIT_CHANGES" ]
		then
  	  if [ "$GERRIT_PROJECT" = "$GERRITDEVICE" ]
	  	then
	  	echo $GERRITDEVICE > workfile.txt
	  	if [ "$GERRITDEVICE" = "CyanDreamProject/android_device_samsung_tuna" ]
			  then
		  	export DEVICE=maguro
  	  	elif [ "$GERRITDEVICE" =~ "CyanDreamProject/android_device_samsung" ]
			then
		  	export DEVICE=`grep 'CyanDreamProject/android_device_samsung_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "CyanDreamProject/android_device_lge" ]
		  	then
		  	export DEVICE=`grep 'CyanDreamProject/android_device_lge_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "CyanDreamProject/android_device_htc" ]
		  	then
		  	export DEVICE=`grep 'CyanDreamProject/android_device_htc_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "CyanDreamProject/android_device_sony" ]
		  	then
		  	export DEVICE=`grep 'CyanDreamProject/android_device_sony_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "CyanDreamProject/android_device_motorola" ]
		  	then
		  	export DEVICE=`grep 'CyanDreamProject/android_device_motorola_' workfile.txt`
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
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

if [[ "$REPO_BRANCH" =~ "jellybean" || $REPO_BRANCH =~ "cd-4.3" ]]; then 
   JENKINS_BUILD_DIR=jellybean
else
   JENKINS_BUILD_DIR=$REPO_BRANCH
fi

export JENKINS_BUILD_DIR

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ -z "$CORE_BRANCH" ]
then
  CORE_BRANCH=$REPO_BRANCH
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
repo init -u $SYNC_PROTO://github.com/CyanDreamProject/android.git -b $CORE_BRANCH $MANIFEST
check_result "repo init failed."

# make sure ccache is in PATH
if [[ "$REPO_BRANCH" =~ "jellybean" || $REPO_BRANCH =~ "cd-4.3" ]]
then
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.jb_ccache
else
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.ics_ccache
fi

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

mkdir -p .repo/local_manifests
rm -f .repo/local_manifest.xml
rm -f .repo/local_manifests/device.xml

rm -rf $WORKSPACE/local_manifests
git clone https://github.com/CyanDreamProject/local_manifests.git $WORKSPACE/local_manifests

if [ "$DEVICE" = "ace" ]
then
  cp $WORKSPACE/local_manifests/ace_manifest.xml .repo/local_manifests/device.xml
elif [ "$DEVICE" = "bravo" ]
then
  cp $WORKSPACE/local_manifests/bravo_manifest.xml .repo/local_manifests/device.xml
else
  echo a local_manifest does not exist, skipping.
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

if [ -f $WORKSPACE/hudson/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/hudson/$REPO_BRANCH-setup.sh
else
  $WORKSPACE/hudson/cm-setup.sh
fi

# workaround for devices that are not 100% supported by CyanDream
echo creating symlink...
ln -s vendor/cyandream vendor/cm

if [ -f .last_branch ]
then
  LAST_BRANCH=$(cat .last_branch)
else
  echo "Last build branch is unknown, assume clean build"
  LAST_BRANCH=$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST
fi

if [ "$LAST_BRANCH" != "$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST" ]
then
  echo "Branch has changed since the last build happened here. Forcing cleanup."
  CLEAN="true"
fi

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
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests/* $TEMPSTASH
mv $TEMPSTASH/roomservice.xml .repo/local_manifests/

# save it
repo manifest -o $WORKSPACE/archive/manifest.xml -r

# restore all local manifests
mv $TEMPSTASH/* .repo/local_manifests/ 2>/dev/null
rmdir $TEMPSTASH

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
    if [ "$REPO_BRANCH" = "gingerbread" ]
    then
      export CYANOGEN_NIGHTLY=true
    else
      export CD_NIGHTLY=true
    fi
  else
    export CD_EXPERIMENTAL=true
  fi
elif [ "$RELEASE_TYPE" = "CD_EXPERIMENTAL" ]
then
  export CD_EXPERIMENTAL=true
elif [ "$RELEASE_TYPE" = "CD_RELEASE" ]
then
  # gingerbread needs this
  export CYANOGEN_RELEASE=true
  # ics needs this
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

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "50.0" ]
then
  ccache -M 50G
fi

WORKSPACE=$WORKSPACE LUNCH=$LUNCH bash $WORKSPACE/hudson/changes/buildlog.sh 2>&1

LAST_CLEAN=0
if [ -f .clean ]
then
  LAST_CLEAN=$(date -r .clean +%s)
fi
TIME_SINCE_LAST_CLEAN=$(expr $(date +%s) - $LAST_CLEAN)
# convert this to hours
TIME_SINCE_LAST_CLEAN=$(expr $TIME_SINCE_LAST_CLEAN / 60 / 60)
if [ $TIME_SINCE_LAST_CLEAN -gt "24" -o $CLEAN = "true" ]
then
  echo "Cleaning!"
  touch .clean
  make clobber
else
  echo "Skipping clean: $TIME_SINCE_LAST_CLEAN hours since last clean."
fi

echo "$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST" > .last_branch

time mka bacon recoveryzip recoveryimage

check_result "Build failed."

if [ "$SIGN_BUILD" = "true" ]
then
  MODVERSION=$(cat $OUT/system/build.prop | grep ro.modversion | cut -d = -f 2)
  if [ ! -z "$MODVERSION" -a -f $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip ]
  then
    ./build/tools/releasetools/sign_target_files_apks -e Term.apk= -d vendor/cd-priv/keys $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip $OUT/$MODVERSION-signed-intermediate.zip
    ./build/tools/releasetools/ota_from_target_files -k vendor/cd-priv/keys/releasekey $OUT/$MODVERSION-signed-intermediate.zip $WORKSPACE/archive/CyanDream-$MODVERSION-signed.zip
  else
    echo "Unable to find target files to sign"
    exit 1
  fi
>>>>>>> 4409dcd094cde3f2ab5e6eb706c8babe153fb390
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
ZIP=$(ls $WORKSPACE/archive/CyanDream-*.zip)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

# CORE: save manifest used for build (saving revisions as current HEAD)
rm -f .repo/local_manifests/dyn-$REPO_BRANCH.xml
rm -f .repo/local_manifests/roomservice.xml

# Stash away other possible manifests
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests $TEMPSTASH

repo manifest -o $WORKSPACE/archive/core.xml -r

mv $TEMPSTASH/local_manifests .repo
rmdir $TEMPSTASH

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive
