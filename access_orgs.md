# ACCESS CI Organizations

When a user registers for a new ACCESS CI account, they must choose an
organization that exists in the ACCESS central database. This list of
organization is synced with COmanage Registry on a regular basis so that
COmanage can display an interactive input textbox to the user.

This list of organizations can be read from the COmanage Registry database.
Log on to one of the AWS bastion hosts in us-east-2 (Ohio) and run the
following command.

```
mysql -u cilogon_master -p \
      -h db.cilogon.org \
      -e 'select name from access_registry.cm_access_organizations order by name;' \
      | tee /tmp/access_orgs.txt
```

The password for the `cilogon_master` account is stored in the
"Shared-NCSA-CILogon" LastPass folder in the "Amazon RDS Aurora" entry.

The resulting file `/tmp/access_orgs.txt` contains some cruft at the top of
the file which should be removed before sharing with others.

Organizations can be added to the ACCESS central database by sending a
help request to support@access-ci.atlassian.net .
