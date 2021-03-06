#!/bin/bash

cd $WORKSPACE

TOX_LOG=$WORKSPACE/.tox/venv/log/venv-1.log 
TMP_LOG=/tmp/tox.log
LOG_FILE=/tmp/tox_log.log

screen -S savanna-api -X quit
rm -f /tmp/savanna-server.db
rm -rf /tmp/cache
rm -f $LOG_FILE

BUILD_ID=dontKill

sudo pip install tox
mkdir /tmp/cache

export ADDR=`ifconfig eth0| awk -F ' *|:' '/inet addr/{print $4}'`

echo "[DEFAULT]
os_auth_host=172.18.168.2
os_auth_port=5000
os_admin_username=ci-user
os_admin_password=swordfish
os_admin_tenant_name=ci
use_neutron=true
plugins=vanilla,hdp
[cluster_node]
[sqlalchemy]
[plugin:vanilla]
plugin_class=savanna.plugins.vanilla.plugin:VanillaProvider
[plugin:hdp]
plugin_class=savanna.plugins.hdp.ambariplugin:AmbariPlugin" >> etc/savanna/savanna.conf

echo "
[global] 
timeout = 60
index-url = http://savanna-ci.vm.mirantis.net/pypi/savanna/
extra-index-url = https://pypi.python.org/simple/
download-cache = /home/ubuntu/.pip/cache/
[install]
use-mirrors = true
find-links = http://savanna-ci.vm.mirantis.net:8181/simple/
" > ~/.pip/pip.conf
screen -dmS savanna-api /bin/bash -c "tox -evenv -- savanna-api --config-file etc/savanna/savanna.conf -d --log-file log.txt | tee /tmp/tox-log.txt"


export ADDR=`ifconfig eth0| awk -F ' *|:' '/inet addr/{print $4}'`

echo "[COMMON]
OS_USERNAME = 'ci-user'
OS_PASSWORD = 'swordfish'
OS_TENANT_NAME = 'ci'
OS_AUTH_URL = 'http://172.18.168.2:5000/v2.0'
SAVANNA_HOST = '$ADDR'
FLAVOR_ID = '22'
CLUSTER_CREATION_TIMEOUT = 60
CLUSTER_NAME = 'ci-$BUILD_NUMBER-$GERRIT_CHANGE_NUMBER-$GERRIT_PATCHSET_NUMBER'
USER_KEYPAIR_ID = 'public-jenkins'
PATH_TO_SSH_KEY = '/home/ubuntu/.ssh/id_rsa'
FLOATING_IP_POOL = 'net04_ext'
NEUTRON_ENABLED = True
INTERNAL_NEUTRON_NETWORK = 'net04'
$COMMON_PARAMS
" >> $WORKSPACE/savanna/tests/integration/configs/itest.conf

echo "[VANILLA]
$VANILLA_PARAMS
" >> $WORKSPACE/savanna/tests/integration/configs/itest.conf

echo "[HDP]
SKIP_ALL_TESTS_FOR_PLUGIN = False
$HDP_PARAMS
" >> $WORKSPACE/savanna/tests/integration/configs/itest.conf

touch $TMP_LOG
i=0

while true
do
        let "i=$i+1"
        diff $TOX_LOG $TMP_LOG >> $LOG_FILE
        cp -f $TOX_LOG $TMP_LOG
        if [ "$i" -gt "240" ]; then
                cat $LOG_FILE
                echo "project does not start" && FAILURE=1 && break
        fi
        if [ ! -f $WORKSPACE/log.txt ]; then
                sleep 10
        else
                echo "project is started" && FAILURE=0 && break
        fi
done

if [ "$FAILURE" = 0 ]; then
   
    cd $WORKSPACE && \
    sed -i "/python-savannaclient.*/d" test-requirements.txt && \
    echo "-f http://tarballs.openstack.org/python-savannaclient/python-savannaclient-master.tar.gz#egg=python-savannaclient-master" >> test-requirements.txt && \
    echo "python-savannaclient==master" >> test-requirements.txt && \
    tox -e integration
fi

echo "-----------Python integration env-----------"
cd $WORKSPACE && .tox/integration/bin/pip freeze

screen -S savanna-api -X quit

echo "-----------Python savanna env-----------"
cd $WORKSPACE && .tox/venv/bin/pip freeze

echo "-----------Savanna Log------------"
cat $WORKSPACE/log.txt
rm -rf /tmp/workspace/
rm -rf /tmp/cache/

echo "-----------Tox log-----------"
cat /tmp/tox-log.txt
rm -f /tmp/tox-log.txt

rm -f /tmp/savanna-server.db
rm $TMP_LOG
rm -f $LOG_FILE

if [ "$FAILURE" != 0 ]; then
    exit 1
fi
