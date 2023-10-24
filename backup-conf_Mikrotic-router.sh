#/bin/bash


Router_IP="192.168.1.1"
Router_Username="admin"
#Router_Password="admin"

File_Name=$(date +'%d-%m-%Y')

local_path_to_save="/your/path/to/save/backup"

SSH_Export_Conf="/export file=Configuration"
SSH_Export_Backup="/system backup save name=Backup dont-encrypt=yes password=admin encryption=aes-sha256"


#sshpass -p "$Router_Password" 
ssh -i /home/jean-lou/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP" "$SSH_Export_Conf"
#sshpass -p "$Router_Password" 
ssh -i /home/jean-lou/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP" "$SSH_Export_Backup"

scp -i /home/jean-lou/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP":Configuration.rsc "$local_path_to_save/$File_Name-Conf.src"
scp -i /home/jean-lou/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP":Backup.backup "$local_path_to_save/$File_Name-Back.backup"





