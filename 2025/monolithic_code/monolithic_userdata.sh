#!/bin/bash -xe
apt update -y
snap install aws-cli --classic
apt install nodejs unzip wget npm mysql-client tree nmap -y
cd /home/ubuntu
git clone https://github.com/ddps-lab/architect-cloud.git
cd /home/ubuntu/architect-cloud/2025
chown ubuntu -R monolithic_code/
cd monolithic_code
npm install

#RDS setup
#######################################
export RDS_DB_EP=!!!Must Modify!!!
#######################################
echo "export RDS_DB_EP=${RDS_DB_EP}" >> /home/ubuntu/.bashrc

# 사용자 생성 
mysql -u admin -plab-password -h ${RDS_DB_EP} -P 3306 -e "
    CREATE USER IF NOT EXISTS 'nodeapp'@'%' IDENTIFIED WITH mysql_native_password BY 'coffee';
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, CREATE USER, EVENT, TRIGGER ON *.* TO 'nodeapp'@'%' WITH GRANT OPTION;"

# DB 생성 
mysql -u admin -plab-password -h ${RDS_DB_EP} -P 3306 -e "CREATE DATABASE IF NOT EXISTS COFFEE;"

# 테이블 생성
mysql -u admin -plab-password -h ${RDS_DB_EP} -P 3306 -e "
    USE COFFEE;
    CREATE TABLE IF NOT EXISTS suppliers (
        id INT NOT NULL AUTO_INCREMENT,
        name VARCHAR(255) NOT NULL,
        address VARCHAR(255) NOT NULL,
        city VARCHAR(255) NOT NULL,
        state VARCHAR(255) NOT NULL,
        email VARCHAR(255) NOT NULL,
        phone VARCHAR(100) NOT NULL,
        PRIMARY KEY (id)
    );"
#sed the config file
sed -i "s|REPLACE-DB-HOST|${RDS_DB_EP}|g" /home/ubuntu/architect-cloud/2025/monolithic_code/app/config/config.js
sleep 2

#start the app
node index.js &

#ensure app starts at boot for all lab sessions
cat <<EOF > /etc/rc.local
#!/bin/bash
cd /home/ubuntu/architect-cloud/2025/monolithic_code/
sudo node index.js
EOF
chmod +x /etc/rc.local
