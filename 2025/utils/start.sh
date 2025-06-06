#!/bin/bash -xe
apt update -y
apt install nodejs unzip wget npm mysql-server tree nmap -y
snap install --classic aws-cli
cd /home/ubuntu
git clone https://github.com/ddps-lab/architect-cloud.git
cd /home/ubuntu/architect-cloud/2025
chown ubuntu -R monolithic_code/
cd monolithic_code
npm install
mysql -u root -e "CREATE USER 'nodeapp' IDENTIFIED WITH mysql_native_password BY 'coffee'";
mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, CREATE USER, EVENT, TRIGGER ON *.* TO 'nodeapp'@'%' WITH GRANT OPTION;"
mysql -u root -e "CREATE DATABASE COFFEE;"
mysql -u root -e "USE COFFEE; CREATE TABLE suppliers(id INT NOT NULL AUTO_INCREMENT,name VARCHAR(255) NOT NULL,address VARCHAR(255) NOT NULL,city VARCHAR(255) NOT NULL,state VARCHAR(255) NOT NULL,email VARCHAR(255) NOT NULL,phone VARCHAR(100) NOT NULL,PRIMARY KEY ( id ));"

sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl enable mysql
service mysql restart
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export APP_DB_HOST=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 -H "X-aws-ec2-metadata-token: $TOKEN")
export APP_DB_USER=nodeapp
export APP_DB_PASSWORD=coffee
export APP_DB_NAME=COFFEE
export APP_PORT=80

node index.js &


cat <<EOF > /etc/rc.local
#!/bin/bash
cd /home/ubuntu/architect-cloud/2024/monolithic_code
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export APP_DB_HOST=$(curl http://169.254.169.254/latest/meta-data/local-ipv4 -H "X-aws-ec2-metadata-token: $TOKEN")
export APP_DB_USER=nodeapp
export APP_DB_PASSWORD=coffee
export APP_DB_NAME=COFFEE
export APP_PORT=80

node index.js
EOF
chmod +x /etc/rc.local
