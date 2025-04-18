# ACCESS Bulk Enroller

This repository contains a scripts to enroll users into an ACCESS COmanage
Registry using name, organization, and email address. The scripts
requires `curl`, `jq`, and `dig` to be installed. Help is available by using
the `-h` command line option. 

## Initial Setup

This script uses the [COmanage Registry REST API
v1](https://spaces.at.internet2.edu/display/COmanage/REST+API+v1) and the
[COmanage Registry Core
API](https://spaces.at.internet2.edu/display/COmanage/Core+API). To connect
to these API endpoints, you must create a new COmanage API user. You can
create as many API users as you like. 

To create an API user, log in to the appropriate ACCESS COmanage
Registry for [DEV](https://registry-dev.access-ci.org/),
[TEST](https://registry-test.access-ci.org/), or
[PROD](https://registry.access-ci.org/) as a platform administrator or a CO
administrator. If logged in as a plaform administrator, select the
"Users" Collaboration. Then:

1. In the left column, select "Configuration".
1. In the main window, click "API Users".
1. Click "+ Add API user" in the upper-right.
1. Select a unique name for the user such as `bulk_api_user`. `co_2.`
   will be prepended to the resulting user name. Check the "Privileged"
   checkbox. Then click the "ADD" button.
1. Back on the "API Users" page, click the newly added API User Name.
1. On the "Edit co\_2.bulk\_api\_user" page, click the "Generate API Key"
   button.
1. You will be shown the API User name and API Key (a.k.a., password).
   Record these values since the API Key will not be shown again. You can
   generate a new API Key if you lose this one.
1. In the left column, select "Configuration".
1. In the main window, click "Core APIs".
1. Click "+ Add Core API" in the upper-right.
1. On the "Add a New Core API" page, set the following values:
   - Status: Active
   - API: COmanage CO Person Write API
   - API User: the API user you just created
   - Identifier: ACCESS ID
   - Response Type: Full Profile
   - Expunge on Delete: Unchecked  
   Then click the "ADD" button.

The API User Name and API Key (password) are required to run the
`access-bulk-enroller.sh` script. You can specify them via command line
options `-u` and `-p` or via environment variables `CO_API_USER` and
`CO_API_PASS`. You will be prompted for them if not otherwise set.

## Validation Script

If you are enrolling multiple users with a CSV file, you can validate the
contents of the CSV file before attempting to run the
`access-bulk-enroller.sh` script. This will ensure that names, organizations,
and email addresses all have a valid format.

The input file (`bulk-enrollment.csv` by default) should have lines of the
following format:

```
firstname,middlename,lastname,organization,emailaddress
```

Note that `middlename` can be empty/blank, but all other attributes are
required.

The `organization` must match one of the Organizations in the ACCESS central
database. See [ACCESS CI Organizations](access_orgs.md) for more
information.

```
Usage: ./validate-csv.sh [options]

Validate a CSV file of users to be bulk-enrolled in ACCESS COmanage
Registry. This script scans a CSV file and checks each line for possible
issues. A list of ACCESS Organizations is also needed during validation.
If the list of ACCESS organizations cannot be found, it will be downloaded
automatically.

Options:
    -i <infile> Input CSV file containing a list of users to be enrolled.
       Defaults to 'bulk-enrollment.csv'. Each line of the file contains
       firstname,middlename,lastname,organizaton,email address
       (i.e., user attributes separated by commas).
    -g <orgfile> File containing the list of ACCESS Organizations, one
       organization per line. Defaults to 'access_orgs.txt'. If the file
       is not found, it will be downloaded to the current directory.
    -o <outfile> Output validation results to a file. Defaults to STDOUT.
    -v Print additional informational and warning messages to STDERR.
    -h Print this help message and quit.
```

## Bulk Enrollment Script

```
Usage: ./access-bulk-enroller.sh [options]

Enroll new users in ACCESS COmanage Registry using name and email address.
Note that 'curl' errors are fatal and will halt the script if they occur.

Options:
    -s <server> ACCESS COmanage Registry server. Defaults to
       registry.access-ci.org.  Can also be set with environment variable
       CO_API_SERVER. For the TEST COmanage server, use
       registry-test.access-ci.org. For the DEV COmanage server, use
       registry-dev.access-ci.org.
    -u <username> Username for connecting to COmanage Registry API
       endpoints. Can also be set with environment variable CO_API_USER. If
       not specified, you will be prompted to enter.
    -p <password> Password for connecting to COmanage Registry API
       endpoints. Can also be set with environment variable CO_API_PASS. If
       not specified, you will be prompted to enter.
    -f <firstname> First name of a single user to be enrolled.
    -m <middlename> Middle name of a single user to be enrolled. May be
       emtpy (e.g., '').
    -l <lastname> Last name of a single user to be enrolled.
    -g <organization> Organization of a single user to be enrolled.
    -e <email> Email address of a single user to be enrolled.
    -i <infile> Input CSV file containing a list of users to be enrolled.
       Each line contains first name, middle name, last name, organizaton,
       and email address, separated by commas. Overrides -f,-m,-l,-g,-e.
    -o <outfile> Output CSV file for the newly enrolled users. Defaults to
       STDOUT.  Each line contains first name, middle name, last name,
       organization, email address, and ACCESS ID, separated by commas.
    -v Print additional informational and warning messages to STDERR.
    -h Print this help message and quit.
```

If you run the script without any command line options, you will be prompted
for all information necessary to add a **single user** to the ACCESS COmanage
Registry. The resulting ACCESS ID will be printed to STDOUT.

To enroll multiple users, specify the `-i <infile>` option with a CSV file
that has been validated with the `validate-csv.sh` script.

By default, output is to STDOUT. This can be overridden with the
`-o <outfile>` option. The resulting outfile is a CSV file where each line
is of the following format:

```
firstname,middlename,lastname,organization,emailaddress,accessid
```
