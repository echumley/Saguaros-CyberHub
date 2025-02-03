# Wazuh Congiguration File

`ossec.conf` is the main configuration file to the Wazuh manager. It's been modified to fit my needs, such as enabling the syslog server funcationality. This file is copied into the VM during deployment, but any changes post-deployment should be done on the Wazuh server at `/var/etc/ossec/ossec.conf`.