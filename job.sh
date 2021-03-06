if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

export WORKSPACE=$PWD

if [ ! -d hudson ]
then
  git clone git://github.com/CyanDreamProject/hudson.git
fi

cd hudson
## Get rid of possible local changes
git reset --hard
git pull -s resolve
chmod +x build.sh

exec ./build.sh
