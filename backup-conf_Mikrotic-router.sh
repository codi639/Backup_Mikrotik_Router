#/bin/bash


Router_IP="192.168.1.1"
Router_Username="admin"
#Router_Password="admin" # You can use this line if you don't want to use ssh keys. If you want to use ssh keys, comment this line and uncomment the 'sshpass' lines. You also need to delete the '-i' option in the 'ssh' and 'scp' lines.

File_Name=$(date +'%d-%m-%Y')

local_path_to_save="/your/local/path/to/save"

SSH_Export_Conf="/export file=Configuration"
SSH_Export_Backup="/system backup save name=Backup dont-encrypt=yes password=password encryption=aes-sha256" # You can cange the encryption type between aes-sha256 and cr4. You might, as well, change the password.

# You might need to change the id_rsa.pub path.

#sshpass -p "$Router_Password" 
ssh -i ~/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP" "$SSH_Export_Conf"
#sshpass -p "$Router_Password" 
ssh -i ~/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP" "$SSH_Export_Backup"

#sshpass -p "$Router_Password"
scp -i ~/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP":Configuration.rsc "$local_path_to_save/$File_Name-Conf.src"
#sshpass -p "$Router_Password" 
scp -i ~/.ssh/id_rsa.pub "$Router_Username"@"$Router_IP":Backup.backup "$local_path_to_save/$File_Name-Back.backup"





