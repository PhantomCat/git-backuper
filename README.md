# Backuping script set for studio git repos

For the first of allget the repository list that you're want to back up.
 - To get the repository list in .json format you have to use gitlab api:
   - `https://your-gitlab-host/api/v4/projects`
      You can automate this, but I don't see the need of that step
 - After that, you need to save the .json file in directory, naming it like as:
   - gbkp_YOUR-REPO-NAME.json, the script will find it as the `gbkp*.json`

Second step - run the install script from superuser.
 - `sudo ./install.sh`
 - If you want to change parameters - change `/etc/gbkp.conf` file
 - If you want to add the repositories list to existing - put the new file in this directory and run the install script again with parameter `--add-json`
 - If you want to change the repositories list - put the new file in this directory and run the install script again with parameter `--new-json`


