#!/bin/bash

# fail immediately on error
set -e -x

# echo "$0 $*" > ~/provision.log

fail() {
  echo "$*" >&2
  exit 1
}

# Variables passed in from terraform, see openstack-cf-install.tf, the "remote-exec" provisioner
OS_USERNAME=${1}
OS_API_KEY=${2}
OS_TENANT=${3}
OS_AUTH_URL=${4}
OS_REGION=${5}
CF_SUBNET1=${6}
IPMASK=${7}
CF_IP=${8}
CF_SIZE=${9}
CF_BOSHWORKSPACE_VERSION=${10}
CF_DOMAIN=${11}
DOCKER_SUBNET=${12}
INSTALL_DOCKER=${13}
LB_SUBNET1=${14}
CF_SG=${15}

BACKBONE_Z1_COUNT=COUNT
API_Z1_COUNT=COUNT
SERVICES_Z1_COUNT=COUNT
HEALTH_Z1_COUNT=COUNT
RUNNER_Z1_COUNT=COUNT
BACKBONE_Z2_COUNT=COUNT
API_Z2_COUNT=COUNT
SERVICES_Z2_COUNT=COUNT
HEALTH_Z2_COUNT=COUNT
RUNNER_Z2_COUNT=COUNT

boshDirectorHost="${IPMASK}.2.4"
cfReleaseVersion="207"

cd $HOME
(("$?" == "0")) ||
  fail "Could not find HOME folder, terminating install."

# Generate the key that will be used to ssh between the bastion and the
# microbosh machine
if [[ ! -f ~/.ssh/id_rsa ]]; then
  ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# Prepare the jumpbox to be able to install ruby and git-based bosh and cf repos

release=$(cat /etc/*release | tr -d '\n')
case "${release}" in
  (*Ubuntu*|*Debian*)
    sudo apt-get update -yq
    sudo apt-get install -yq aptitude
    sudo aptitude -yq install build-essential vim-nox git unzip tree \
      libxslt-dev libxslt1.1 libxslt1-dev libxml2 libxml2-dev \
      libpq-dev libmysqlclient-dev libsqlite3-dev \
      g++ gcc make libc6-dev libreadline6-dev zlib1g-dev libssl-dev libyaml-dev \
      libsqlite3-dev sqlite3 autoconf libgdbm-dev libncurses5-dev automake \
      libtool bison pkg-config libffi-dev cmake
    ;;
  (*Centos*|*RedHat*|*Amazon*)
    sudo yum update -y
    sudo yum install -y epel-release
    sudo yum install -y git unzip xz tree rsync openssl openssl-devel \
    zlib zlib-devel libevent libevent-devel readline readline-devel cmake ntp \
    htop wget tmux gcc g++ autoconf pcre pcre-devel vim-enhanced gcc mysql-devel \
    postgresql-devel postgresql-libs sqlite-devel libxslt-devel libxml2-devel \
    yajl-ruby
    ;;
esac

cd $HOME



# Install RVM

if [[ ! -d "$HOME/rvm" ]]; then
  git clone https://github.com/rvm/rvm
fi

if [[ ! -d "$HOME/.rvm" ]]; then
  cd rvm
  ./install
fi

cd $HOME

if [[ ! "$(ls -A $HOME/.rvm/environments)" ]]; then
  ~/.rvm/bin/rvm install ruby-2.1
fi

if [[ ! -d "$HOME/.rvm/environments/default" ]]; then
  ~/.rvm/bin/rvm alias create default 2.1
fi

source ~/.rvm/environments/default
source ~/.rvm/scripts/rvm

# Install BOSH CLI, bosh-bootstrap, spiff and other helpful plugins/tools
gem install fog-aws -v 0.1.1 --no-ri --no-rdoc --quiet
gem install bundler bosh-bootstrap --no-ri --no-rdoc --quiet

# bosh-bootstrap handles provisioning the microbosh machine and installing bosh
# on it. This is very nice of bosh-bootstrap. Everyone make sure to thank bosh-bootstrap
mkdir -p {bin,workspace/deployments/microbosh,workspace/tools}
pushd workspace/deployments
pushd microbosh
cat <<EOF > settings.yml
---
bosh:
  name: bosh-${OS_TENANT}
provider:
  name: openstack
  credentials:
    openstack_username: ${OS_USERNAME}
    openstack_api_key: ${OS_API_KEY}
    openstack_tenant: ${OS_TENANT}
    openstack_auth_url: ${OS_AUTH_URL}
    openstack_region: ${OS_REGION}
  options:
    boot_from_volume: false
  state_timeout: 600
address:
  subnet_id: ${CF_SUBNET1}
  ip: ${boshDirectorHost}
EOF

if [[ ! -d "$HOME/workspace/deployments/microbosh/deployments" ]]; then
  bosh bootstrap deploy
fi

# We've hardcoded the IP of the microbosh machine, because convenience
bosh -n target https://${boshDirectorHost}:25555
bosh login admin admin

if [[ ! "$?" == 0 ]]; then
  #wipe the ~/workspace/deployments/microbosh folder contents and try again
  echo "Retry deploying the micro bosh..."
fi
popd

# There is a specific branch of cf-boshworkspace that we use for terraform. This
# may change in the future if we come up with a better way to handle maintaining
# configs in a git repo
if [[ ! -d "$HOME/workspace/deployments/cf-boshworkspace" ]]; then
  git clone --branch  ${CF_BOSHWORKSPACE_VERSION} http://github.com/cloudfoundry-community/cf-boshworkspace
fi
pushd cf-boshworkspace
mkdir -p ssh
gem install bundler
bundle install

# Pull out the UUID of the director - bosh_cli needs it in the deployment to
# know it's hitting the right microbosh instance
DIRECTOR_UUID=$(bosh status | grep UUID | awk '{print $2}')

# If CF_DOMAIN is set to XIP, then use XIP.IO. Otherwise, use the variable
if [ $CF_DOMAIN == "XIP" ]; then
  CF_DOMAIN="${CF_IP}.xip.io"
fi

if [[ ! -f "/usr/local/bin/spiff" ]]; then
  curl -sOL https://github.com/cloudfoundry-incubator/spiff/releases/download/v1.0.3/spiff_linux_amd64.zip
  unzip spiff_linux_amd64.zip
  sudo mv ./spiff /usr/local/bin/spiff
  rm spiff_linux_amd64.zip
fi

# This is some hackwork to get the configs right. Could be changed in the future
/bin/sed -i \
  -e "s/CF_SUBNET1/${CF_SUBNET1}/g" \
  -e "s/LB_SUBNET1/${LB_SUBNET1}/g" \
  -e "s|OS_AUTHURL|${OS_AUTH_URL}|g" \
  -e "s/OS_TENANT/${OS_TENANT}/g" \
  -e "s/OS_APIKEY/${OS_API_KEY}/g" \
  -e "s/OS_USERNAME/${OS_USERNAME}/g" \
  -e "s/OS_TENANT/${OS_TENANT}/g" \
  -e "s/CF_ELASTIC_IP/${CF_IP}/g" \
  -e "s/CF_DOMAIN/${CF_DOMAIN}/g" \
  -e "s/CF_SG/${CF_SG}/g" \
  -e "s/DIRECTOR_UUID/${DIRECTOR_UUID}/g" \
  -e "s/backbone_z1:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/backbone_z1:\1${BACKBONE_Z1_COUNT}\2/" \
  -e "s/api_z1:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/api_z1:\1${API_Z1_COUNT}\2/" \
  -e "s/services_z1:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/services_z1:\1${SERVICES_Z1_COUNT}\2/" \
  -e "s/health_z1:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/health_z1:\1${HEALTH_Z1_COUNT}\2/" \
  -e "s/runner_z1:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/runner_z1:\1${RUNNER_Z1_COUNT}\2/" \
  -e "s/backbone_z2:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/backbone_z2:\1${BACKBONE_Z2_COUNT}\2/" \
  -e "s/api_z2:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/api_z2:\1${API_Z2_COUNT}\2/" \
  -e "s/services_z2:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/services_z2:\1${SERVICES_Z2_COUNT}\2/" \
  -e "s/health_z2:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/health_z2:\1${HEALTH_Z2_COUNT}\2/" \
  -e "s/runner_z2:\( \+\)[0-9\.]\+\(.*# MARKER_FOR_PROVISION.*\)/runner_z2:\1${RUNNER_Z2_COUNT}\2/" \
  deployments/cf-openstack-${CF_SIZE}.yml


# Upload the bosh release, set the deployment, and execute
deployedVersion=$(bosh releases | grep " ${cfReleaseVersion}" | awk '{print $4}')
deployedVersion="${deployedVersion//[^[:alnum:]]/}"
if [[ ! "$deployedVersion" == "${cfReleaseVersion}" ]]; then
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=${cfReleaseVersion}
  bosh deployment cf-openstack-${CF_SIZE}
  bosh prepare deployment || bosh prepare deployment  #Seems to always fail on the first run...
else
  bosh deployment cf-openstack-${CF_SIZE}
fi

# Work around until bosh-workspace can handle submodules
if [[ "cf-openstack-${CF_SIZE}" == "cf-openstack-large" ]]; then
  pushd .releases/cf
  ./update
  popd
fi

# We locally commit the changes to the repo, so that errant git checkouts don't
# cause havok
currentGitUser="$(git config user.name || /bin/true )"
currentGitEmail="$(git config user.email || /bin/true )"
if [[ "${currentGitUser}" == "" || "${currentGitEmail}" == "" ]]; then
  git config --global user.email "${USER}@${HOSTNAME}"
  git config --global user.name "${USER}"
  echo "blarg"
fi

gitDiff="$(git diff)"
if [[ ! "${gitDiff}" == "" ]]; then
  git commit -am 'commit of the local deployment configs'
fi


# Keep trying until there is a successful BOSH deploy.
for i in {0..2}
do bosh -n deploy
done

echo "Install Traveling CF"
if [[ "$(cat $HOME/.bashrc | grep 'export PATH=$PATH:$HOME/bin/traveling-cf-admin')" == "" ]]; then
  curl -s https://raw.githubusercontent.com/cloudfoundry-community/traveling-cf-admin/master/scripts/installer | bash
  echo 'export PATH=$PATH:$HOME/bin/traveling-cf-admin' >> $HOME/.bashrc
  source $HOME/.bashrc
fi

# Now deploy docker services if requested
if [[ $INSTALL_DOCKER == "true" ]]; then

  cd ~/workspace/deployments
  if [[ ! -d "$HOME/workspace/deployments/docker-services-boshworkspace" ]]; then
    git clone https://github.com/cloudfoundry-community/docker-services-boshworkspace.git
  fi

  echo "Update the docker-aws-vpc.yml with cf-boshworkspace parameters"
  /home/ubuntu/workspace/deployments/docker-services-boshworkspace/shell/populate-docker-openstack
  dockerDeploymentManifest="/home/ubuntu/workspace/deployments/docker-services-boshworkspace/deployments/docker-openstack.yml"
  /bin/sed -i "s/SUBNET_ID/${DOCKER_SUBNET}/g" "${dockerDeploymentManifest}"

  cd ~/workspace/deployments/docker-services-boshworkspace
  bundle install
  bosh deployment docker-openstack
  bosh prepare deployment

  # Keep trying until there is a successful BOSH deploy.
  for i in {0..2}
  do bosh -n deploy
  done

fi

echo "Provision script completed..."
exit 0

# FIXME: enable this again when smoke_tests work
# bosh run errand smoke_tests
