#!/bin/sh

echo 'INSTALLER: Started up'

# get up to date
yum upgrade -y

echo 'INSTALLER: System updated'

# fix locale warning
yum reinstall -y glibc-common
echo LANG=en_US.utf-8 >> /etc/environment
echo LC_ALL=en_US.utf-8 >> /etc/environment

echo 'INSTALLER: Locale set'

# install Oracle Database prereq packages
yum install -y oracle-database-server-12cR2-preinstall

echo 'INSTALLER: Oracle preinstall complete'

# create directories
mkdir $ORACLE_BASE
chown oracle:oinstall -R $ORACLE_BASE

echo 'INSTALLER: Oracle directories created'

# set environment variables
echo "export ORACLE_BASE=$ORACLE_BASE" >> /home/oracle/.bashrc && \
echo "export ORACLE_HOME=$ORACLE_HOME" >> /home/oracle/.bashrc && \
echo "export ORACLE_SID=$ORACLE_SID" >> /home/oracle/.bashrc   && \
echo "export PATH=\$PATH:\$ORACLE_HOME/bin" >> /home/oracle/.bashrc

echo 'INSTALLER: Environment variables set'

# install Oracle
echo 'INSTALLER: Unpacking Oracle Installer'
unzip -q /vagrant/linux*122*.zip -d /vagrant
echo 'INSTALLER: Creating Oracle install response file'
cp /vagrant/ora-response/db_install.rsp.tmpl /vagrant/ora-response/db_install.rsp
sed -i -e "s|###ORACLE_BASE###|$ORACLE_BASE|g" /vagrant/ora-response/db_install.rsp && \
sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" /vagrant/ora-response/db_install.rsp && \
echo 'INSTALLER: Running Oracle installation'
su -l oracle -c "yes | /vagrant/database/runInstaller -silent -showProgress -ignorePrereq -waitforcompletion -responseFile /vagrant/ora-response/db_install.rsp"
$ORACLE_BASE/oraInventory/orainstRoot.sh
$ORACLE_HOME/root.sh
rm -rf /vagrant/database
rm /vagrant/ora-response/db_install.rsp

echo 'INSTALLER: Oracle software installed'

# create listener via netca
su -l oracle -c "netca -silent -responseFile /vagrant/ora-response/netca.rsp"
echo 'INSTALLER: Listener created'

# create database
echo 'INSTALLER: Creating database creation response file'
cp /vagrant/ora-response/dbca.rsp.tmpl /vagrant/ora-response/dbca.rsp
sed -i -e "s|###ORACLE_SID###|$ORACLE_SID|g" /vagrant/ora-response/dbca.rsp && \
sed -i -e "s|###ORACLE_PDB###|$ORACLE_PDB|g" /vagrant/ora-response/dbca.rsp && \
sed -i -e "s|###ORACLE_CHARACTERSET###|$ORACLE_CHARACTERSET|g" /vagrant/ora-response/dbca.rsp
echo 'INSTALLER: Running database creation'
su -l oracle -c "dbca -silent -createDatabase -responseFile /vagrant/ora-response/dbca.rsp"

echo 'INSTALLER: Running database post-creation tasks'
su -l oracle -c "sqlplus / as sysdba <<EOF
   ALTER SYSTEM SET max_string_size=extended scope=spfile;
   SHUTDOWN IMMEDIATE;
   STARTUP UPGRADE;
   EXIT;
EOF"

su -l oracle -c "cd $ORACLE_HOME/rdbms/admin/ && $ORACLE_HOME/perl/bin/perl catcon.pl -d ${ORACLE_HOME}/rdbms/admin -l /tmp -b utl32k_output utl32k.sql"
su -l oracle -c "cd $ORACLE_HOME/rdbms/admin/ && $ORACLE_HOME/perl/bin/perl catcon.pl -d ${ORACLE_HOME}/rdbms/admin -l /tmp -b utlrp_output utlrp.sql"

su -l oracle -c "sqlplus / as sysdba <<EOF
   SHUTDOWN IMMEDIATE;
   STARTUP;
   EXIT;
EOF"

rm /vagrant/ora-response/dbca.rsp

echo 'INSTALLER: Database created'

sed '$s/N/Y/' /etc/oratab | sudo tee /etc/oratab > /dev/null
echo 'INSTALLER: Oratab configured'

# configure systemd to start oracle instance on startup
sudo cp /vagrant/scripts/oracle-rdbms.service /etc/systemd/system/
sudo sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" /etc/systemd/system/oracle-rdbms.service
sudo systemctl daemon-reload
sudo systemctl enable oracle-rdbms
sudo systemctl start oracle-rdbms
echo "INSTALLER: Created and enabled oracle-rdbms systemd's service"

echo 'INSTALLER: Installation complete, database ready to use!'
