# Mikrotik Router Backup Script

## Uses
These scripts allow you to register a new user on a list of routers. This user can then connect to the routers to retrieve backup files (/export and backup).

## Versions
Both versions of the files perform the same tasks, but retrieve the routers' IP addresses in two different ways: via a database or via a txt file (to be modified as required).

## Additional
The scripts generate error reports, which are sent by Telegram using a bot and by e-mail. You'll need to configure postfix to send them by e-mail.

## Be aware !
Please take the time to read the SSH commands before launching the scripts. They are designed to suit the router versions I use, to be modified as required.
You need to block cron from sending automatic e-mails:
In the crontab file:
`crontab -e`
add the line:
```
# For example, you can run a backup of all your user accounts
# at 5 a.m every week with:
# 0 5 * * 1 tar -zcf /var/backups/home.tgz /home/
# 
# For more information see the manual pages of crontab(5) and cron(8)
# 
# m h  dom mon dow   command
MAILTO:""
0 2 * * * /path/to/your/script/backup_router_database.sh
```
