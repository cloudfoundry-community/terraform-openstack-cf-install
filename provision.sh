#!/bin/bash

# fail immediately on error
set -e

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


boshDirectorHost="${IPMASK}.2.4"
cfReleaseVersion="205"

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
      libtool bison pkg-config libffi-dev
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

# Generate the key that will be used to ssh between the bastion and the
# microbosh machine
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa


# Install RVM
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
curl -sSL https://get.rvm.io | bash -s stable
~/.rvm/bin/rvm  --static install ruby-2.1.5
~/.rvm/bin/rvm alias create default 2.1.5
source ~/.rvm/environments/default


# This volume is created using terraform in aws-bosh.tf
#sudo /sbin/mkfs.ext4 /dev/xvdc
#sudo /sbin/e2label /dev/xvdc workspace
#echo 'LABEL=workspace /home/ubuntu/workspace ext4 defaults,discard 0 0' | sudo tee -a /etc/fstab
#mkdir -p /home/ubuntu/workspace
#sudo mount -a
#sudo chown -R ubuntu:ubuntu /home/ubuntu/workspace

# As long as we have a large volume to work with, we'll move /tmp over there
# You can always use a bigger /tmp
#sudo rsync -avq /tmp/ /home/ubuntu/workspace/tmp/
#sudo rm -fR /tmp
#sudo ln -s /home/ubuntu/workspace/tmp /tmp

# Install BOSH CLI, bosh-bootstrap, spiff and other helpful plugins/tools
gem install git -v 1.2.7  #1.2.9.1 is not backwards compatible
gem install bosh_cli -v 1.2891.0 --no-ri --no-rdoc --quiet
gem install bosh_cli_plugin_micro -v 1.2891.0 --no-ri --no-rdoc --quiet
gem install bosh_cli_plugin_aws -v 1.2891.0 --no-ri --no-rdoc --quiet
gem install bosh-bootstrap bosh-workspace --no-ri --no-rdoc --quiet

# bosh-bootstrap handles provisioning the microbosh machine and installing bosh
# on it. This is very nice of bosh-bootstrap. Everyone make sure to thank bosh-bootstrap
mkdir -p {bin,workspace/deployments/microbosh,workspace/tools}
pushd workspace/deployments
pushd microbosh
cat <<EOF > settings.yml
---
bosh:
  name: firstbosh
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

bosh bootstrap deploy

# We've hardcoded the IP of the microbosh machine, because convenience
bosh -n target https://${boshDirectorHost}:25555
bosh login admin admin
popd

# There is a specific branch of cf-boshworkspace that we use for terraform. This
# may change in the future if we come up with a better way to handle maintaining
# configs in a git repo
git clone --branch  ${CF_BOSHWORKSPACE_VERSION} http://github.com/cloudfoundry-community/cf-boshworkspace
pushd cf-boshworkspace
mkdir -p ssh

bundle install

# Pull out the UUID of the director - bosh_cli needs it in the deployment to
# know it's hitting the right microbosh instance
DIRECTOR_UUID=$(bosh status | grep UUID | awk '{print $2}')

# If CF_DOMAIN is set to XIP, then use XIP.IO. Otherwise, use the variable
if [ $CF_DOMAIN == "XIP" ]; then
  CF_DOMAIN="${CF_IP}.xip.io"
fi

curl -sOL https://github.com/cloudfoundry-incubator/spiff/releases/download/v1.0.3/spiff_linux_amd64.zip
unzip spiff_linux_amd64.zip
sudo mv ./spiff /usr/local/bin/spiff
rm spiff_linux_amd64.zip

# This is some hackwork to get the configs right. Could be changed in the future
/bin/sed -i \
  -e "s/CF_SUBNET1/${CF_SUBNET1}/g" \
  -e "s|OS_AUTHURL|${OS_AUTH_URL}|g" \
  -e "s/OS_TENANT/${OS_TENANT}/g" \
  -e "s/OS_APIKEY/${OS_API_KEY}/g" \
  -e "s/OS_USERNAME/${OS_USERNAME}/g" \
  -e "s/OS_TENANT/${OS_TENANT}/g" \
  -e "s/CF_ELASTIC_IP/${CF_IP}/g" \
  -e "s/CF_DOMAIN/${CF_DOMAIN}/g" \
  -e "s/DIRECTOR_UUID/${DIRECTOR_UUID}/g" \
  deployments/cf-openstack-${CF_SIZE}.yml


# Upload the bosh release, set the deployment, and execute
bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=${cfReleaseVersion}
bosh deployment cf-openstack-${CF_SIZE}
bosh prepare deployment

# We locally commit the changes to the repo, so that errant git checkouts don't
# cause havok
#git commit -am 'commit of the local deployment configs'

# Speaking of hack-work, bosh deploy often fails the first or even second time, due to packet bats
# We run it three times (it's idempotent) so that you don't have to
for i in {0..2}
do bosh -n deploy
done


echo "Install Traveling CF"
curl -s https://raw.githubusercontent.com/cloudfoundry-community/traveling-cf-admin/master/scripts/installer | bash
echo 'export PATH=$PATH:$HOME/bin/traveling-cf-admin' >> ~/.bashrc

# Now deploy docker services if requested
if [[ $INSTALL_DOCKER == "true" ]]; then

  cd ~/workspace/deployments
  git clone https://github.com/cloudfoundry-community/docker-services-boshworkspace.git

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

# FIXME: enable this again when smoke_tests work
# bosh run errand smoke_tests
