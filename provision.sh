#!/bin/bash

# fail immediately on error
set -e

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
CF_RELEASE_VERSION=${16}

HTTP_PROXY=${17}
HTTPS_PROXY=${18}

OPENSTACK_IP=$(echo $OS_AUTH_URL | grep -E -o "([0-9]{1,3}[.]){3}[0-9]{1,3}")
LB_WHITELIST="$(echo LB_WHITELIST_IPS | sed 's/ /,/g')"
CF_WHITELIST="$(echo CF_WHITELIST_IPS | sed 's/ /,/g')"
DK_WHITELIST="$(echo DK_WHITELIST_IPS | sed 's/ /,/g')"
NO_PROXY="LOCALHOST_WHITELIST,$LB_WHITELIST,$CF_WHITELIST,$DK_WHITELIST,$OPENSTACK_IP"

DEBUG=${19}

PRIVATE_DOMAINS=${20}

INSTALL_LOGSEARCH=${21}
LS1_SUBNET=${22}
CF_SG_ALLOWS=${23}

DNS1=${24}
DNS2=${25}

OS_TIMEOUT=${26}

DOCKER_BOSHWORKSPACE_VERSION=master

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

BACKBONE_POOL=POOL
DATA_POOL=POOL
PUBLIC_HAPROXY_POOL=POOL
PRIVATE_HAPROXY_POOL=POOL
API_POOL=POOL
SERVICES_POOL=POOL
HEALTH_POOL=POOL
RUNNER_POOL=POOL

boshDirectorHost="${IPMASK}.2.4"

if [[ $DEBUG == "true" ]]; then
  set -x
fi

cd $HOME
(("$?" == "0")) ||
  fail "Could not find HOME folder, terminating install."


# Setup proxy
if [[ $HTTP_PROXY != "" || $HTTPS_PROXY != "" ]]; then
  if [[ ! -f /etc/profile.d/http_proxy.sh ]]; then
    cat <<EOF > http_proxy.sh
#!/bin/bash
export http_proxy=${HTTP_PROXY}
export https_proxy=${HTTPS_PROXY}
export no_proxy=${NO_PROXY}
EOF
  sudo cp http_proxy.sh /etc/profile.d/http_proxy.sh
  source http_proxy.sh
  echo "Acquire::http::proxy \"${HTTP_PROXY}\";" > 100proxy
  echo "Acquire::https::proxy \"${HTTPS_PROXY}\";" >> 100proxy
  sudo cp 100proxy /etc/apt/apt.conf.d/100proxy
  fi
fi


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

if [[ ! -d "$HOME/.rvm" ]]; then
  cd $HOME
  gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
  curl -sSL https://get.rvm.io | bash -s stable
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
create_settings_yml() {
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
  state_timeout: ${OS_TIMEOUT}
address:
  subnet_id: ${CF_SUBNET1}
  ip: ${boshDirectorHost}
EOF
}

if [[ ! -f "$HOME/workspace/deployments/microbosh/settings.yml" ]]; then
  create_settings_yml
fi

if [[ $HTTP_PROXY != ""  || $HTTPS_PROXY != ""  ]]; then
  cat <<EOF >> settings.yml
proxy:
  http_proxy: ${HTTP_PROXY}
  https_proxy: ${HTTPS_PROXY}
  no_proxy: ${NO_PROXY}
EOF
fi

if [[ ! -d "$HOME/workspace/deployments/microbosh/deployments" ]]; then
  bosh bootstrap deploy
fi

rebuild_micro_bosh_easy() {
  echo "Retry deploying the micro bosh, attempting bosh bootstrap delete..."
  bosh bootstrap delete || rebuild_micro_bosh_hard
  bosh bootstrap deploy
  bosh -n target https://${boshDirectorHost}:25555
  bosh login admin admin
}

rebuild_micro_bosh_hard() {
  echo "Retry deploying the micro bosh, attempting bosh bootstrap delete..."
  rm -rf "$HOME/workspace/deployments/microbosh/deployments"
  rm -rf "$HOME/workspace/deployments/microbosh/ssh"
  create_settings_yml
}

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

echo "Install Traveling CF"
if [[ "$(cat $HOME/.bashrc | grep 'export PATH=$PATH:$HOME/bin/traveling-cf-admin')" == "" ]]; then
  curl -s https://raw.githubusercontent.com/cloudfoundry-community/traveling-cf-admin/master/scripts/installer | bash
  echo 'export PATH=$PATH:$HOME/bin/traveling-cf-admin' >> $HOME/.bashrc
  source $HOME/.bashrc
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
  -e "s/version: \+[0-9]\+ \+# DEFAULT_CF_RELEASE_VERSION/version: ${CF_RELEASE_VERSION}/g" \
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
  -e "s|~ # HTTP_PROXY|${HTTP_PROXY}|" \
  -e "s|~ # HTTPS_PROXY|${HTTPS_PROXY}|" \
  -e "s/~ # NO_PROXY/${NO_PROXY}/" \
  -e "s/backbone:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/backbone:\1${BACKBONE_POOL}\2/" \
  -e "s/data:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/data:\1${DATA_POOL}\2/" \
  -e "s/public_haproxy:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/public_haproxy:\1${PUBLIC_HAPROXY_POOL}\2/" \
  -e "s/private_haproxy:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/private_haproxy:\1${PRIVATE_HAPROXY_POOL}\2/" \
  -e "s/api:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/api:\1${API_POOL}\2/" \
  -e "s/services:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/services:\1${SERVICES_POOL}\2/" \
  -e "s/health:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/health:\1${HEALTH_POOL}\2/" \
  -e "s/runner:\( \+\)[a-z\-\_A-Z0-1]\+\(.*# MARKER_FOR_POOL_PROVISION.*\)/runner:\1${RUNNER_POOL}\2/" \
  deployments/cf-openstack-${CF_SIZE}.yml

if [[ -n "$PRIVATE_DOMAINS" ]]; then
  for domain in $(echo $PRIVATE_DOMAINS | tr "," "\n"); do
    sed -i -e "s/^\(\s\+\)- PRIVATE_DOMAIN_PLACEHOLDER/\1- $domain\n\1- PRIVATE_DOMAIN_PLACEHOLDER/" deployments/cf-openstack-${CF_SIZE}.yml
  done
  sed -i -e "s/^\s\+- PRIVATE_DOMAIN_PLACEHOLDER//" deployments/cf-openstack-${CF_SIZE}.yml
else
  sed -i -e "s/^\(\s\+\)internal_only_domains:\$/\1internal_only_domains: []/" deployments/cf-openstack-${CF_SIZE}.yml
  sed -i -e "s/^\s\+- PRIVATE_DOMAIN_PLACEHOLDER//" deployments/cf-openstack-${CF_SIZE}.yml
fi

if [[ -n "$CF_SG_ALLOWS" ]]; then
  replacement_text=""
  for cidr in $(echo $CF_SG_ALLOWS | tr "," "\n"); do
    if [[ -n "$cidr" ]]; then
      replacement_text="${replacement_text}{\"protocol\":\"all\",\"destination\":\"${cidr}\"},"
    fi
  done
  if [[ -n "$replacement_text" ]]; then
    replacement_text=$(echo $replacement_text | sed 's/,$//')
    sed -i -e "s|^\(\s\+additional_security_group_rules:\s\+\).*|\1[$replacement_text]|" deployments/cf-openstack-${CF_SIZE}.yml
  fi
fi

if [[ $INSTALL_LOGSEARCH == "true" ]]; then
    if [[ $(grep -v syslog deployments/cf-openstack-${CF_SIZE}.yml)  ]]; then
        INSERT_AT=$(grep -n cf-networking.yml deployments/cf-openstack-${CF_SIZE}.yml  | cut -d : -f 1)
        sed -i "${INSERT_AT}i\ \ - cf-syslog.yml" deployments/cf-openstack-${CF_SIZE}.yml

        cat <<EOF >> deployments/cf-openstack-${CF_SIZE}.yml

  syslog_daemon_config:
    address: ${IPMASK}.6.7
    port: 5515
EOF
    fi
fi


bosh upload release --skip-if-exists https://bosh.io/d/github.com/cloudfoundry/cf-release?v=${CF_RELEASE_VERSION}
bosh deployment cf-openstack-${CF_SIZE}
bosh prepare deployment || bosh prepare deployment  #Seems to always fail on the first run...

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

# Run smoke tests
# FIXME: Re-enable smoke tests after they become reliable (experiencing intermittent failures)
#bosh run errand smoke_tests_runner

# Now deploy docker services if requested
if [[ $INSTALL_DOCKER == "true" ]]; then

  cd ~/workspace/deployments
  if [[ ! -d "$HOME/workspace/deployments/docker-services-boshworkspace" ]]; then
    git clone  --branch ${DOCKER_BOSHWORKSPACE_VERSION} https://github.com/cloudfoundry-community/docker-services-boshworkspace.git
  fi

  echo "Update the docker-aws-vpc.yml with cf-boshworkspace parameters"
  /home/ubuntu/workspace/deployments/docker-services-boshworkspace/shell/populate-docker-openstack
  dockerDeploymentManifest="/home/ubuntu/workspace/deployments/docker-services-boshworkspace/deployments/docker-openstack.yml"
  /bin/sed -i \
    -e "s/SUBNET_ID/${DOCKER_SUBNET}/g" \
    -e "s/DOCKER_SG/${CF_SG}/g" \
    -e "s|dns_servers: \+\[.*\]|dns_servers: [\"${DNS1}\", \"${DNS2}\"]|" \
    "${dockerDeploymentManifest}"

  if [[ -n ${HTTP_PROXY} || -n ${HTTPS_PROXY} ]]; then
    /bin/sed -i \
      -e "s|~ # HTTP_PROXY|${HTTP_PROXY}|" \
      -e "s|~ # HTTPS_PROXY|${HTTPS_PROXY}|" \
      -e "s|~ # NO_PROXY|${NO_PROXY}|" \
      "${dockerDeploymentManifest}"
  fi

  cd ~/workspace/deployments/docker-services-boshworkspace
  bundle install
  bosh deployment docker-openstack
  bosh prepare deployment

  # Keep trying until there is a successful BOSH deploy.
  for i in {0..2}
  do bosh -n deploy
  done

fi

# Now deploy logsearch if requested
if [[ $INSTALL_LOGSEARCH == "true" ]]; then

    cd ~/workspace/deployments
    if [[ ! -d "$HOME/workspace/deployments/logsearch-boshworkspace" ]]; then
        git clone https://github.com/cloudfoundry-community/logsearch-boshworkspace.git
    fi

    cd logsearch-boshworkspace

    CF_ADMIN_PASS=c1oudc0wc1oudc0w # Hardcoded in upstream template
    /bin/sed -i \
             -e "s/DIRECTOR_UUID/${DIRECTOR_UUID}/g" \
             -e "s/IPMASK/${IPMASK}/g" \
             -e "s/CF_DOMAIN/run.${CF_DOMAIN}/g" \
             -e "s/CF_ADMIN_PASS/${CF_ADMIN_PASS}/g" \
             -e "s/CLOUDFOUNDRY_SG/${CF_SG}/g" \
             -e "s/LS1_SUBNET/${LS1_SUBNET}/g" \
             deployments/logsearch-openstack.yml

    bundle install
    bosh deployment logsearch-openstack
    bosh prepare deployment

    # Keep trying until there is a successful BOSH deploy.
    for i in {0..2}
    do bosh -n deploy
    done

    es_ip=${IPMASK}.6.6
    # Install kibana dashboard
    cat .releases/logsearch-for-cloudfoundry/target/kibana4-dashboards.json \
        | curl --data-binary @- http://${es_ip}:9200/_bulk

    # Fix Tile Map visualization # http://git.io/vLYabb
    if [[ $(curl -s http://${es_ip}:9200/_template/ | grep -v geo_pointt) ]]; then
        echo "installing default elasticsarch index template"
        curl -XPUT http://${es_ip}:9200/_template/logstash -d \
             '{"template":"logstash-*","order":10,"settings":{"number_of_shards":4,"number_of_replicas":1,"index":{"query":{"default_field":"@message"},"store":{"compress":{"stored":true,"tv":true}}}},"mappings":{"_default_":{"_all":{"enabled":false},"_source":{"compress":true},"_ttl":{"enabled":true,"default":"2592000000"},"dynamic_templates":[{"string_template":{"match":"*","mapping":{"type":"string","index":"not_analyzed"},"match_mapping_type":"string"}}],"properties":{"@message":{"type":"string","index":"analyzed"},"@tags":{"type":"string","index":"not_analyzed"},"@timestamp":{"type":"date","index":"not_analyzed"},"@type":{"type":"string","index":"not_analyzed"},"message":{"type":"string","index":"analyzed"},"message_data":{"type":"object","properties":{"Message":{"type":"string","index":"analyzed"}}},"geoip":{"properties":{"location":{"type":"geo_point"}}}}}}}'

        echo "deleting all indexes since installed template only applies to new indexes"
        curl -XDELETE http://${es_ip}:9200/logstash-*
    fi
fi


echo "Provision script completed..."
exit 0
