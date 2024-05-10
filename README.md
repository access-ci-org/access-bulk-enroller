# ACCESS Bulk Enroller

This repository contains a script to enroll users into an ACCESS COmanage
Registry using just first name, last name, and email address. The script
requires `curl` and `jq` to be installed. Help is available by using the
`-h` command line option. 

## Initial Setup

This script uses the [COmanage Registry REST API
v1](https://spaces.at.internet2.edu/display/COmanage/REST+API+v1) and the
[COmanage Registry Core
API](https://spaces.at.internet2.edu/display/COmanage/Core+API). To connect
to these API endpoints, you must create a new API user. You can create as
many API users as you like. 

To create an API user, log in to the appropriate ACCESS COmanage
Registry for [DEV](https://registry-dev.access-ci.org/),
[TEST](https://registry-test.access-ci.org/), or
[PROD](https://registry.access-ci.org/) as a platform administrator or a CO
administrator. If you logged in as a plaform administrator, select the
"Users" Collaboration. Then:

1. In the left column, select "Configuration".
1. In the main window, click "API Users".
1. Click "+ Add API user" in the upper-right.
1. Select a unique name for the user. `co_2.` will be prepended to the
   resulting user name. Check the "Privileged" checkbox. Then click the
   "ADD" button.
1. Back on the "API Users" page, click the newly added API User Name.
1. On the "Edit co\_2.new\_api\_user" page, click the "Generate API Key"
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

The API User Name and API Key (password) are required to use the script. You
can specify them via command line options `-u` and `-p`, by environment
variables `CO_API_USER` and `CO_API_PASS`, or you can be prompted for them
otherwise.

## Running the Script

```
Usage: ./access-bulk-enroller.sh [options]

Enroll new users in ACCESS COmanage Registry using name and email address.

Options:
    -s ACCESS COmanage Registry server. Defaults to registry.access-ci.org.
       Can also be set with environment variable CO_API_SERVER.
    -u Username for connecting to COmanage Registry API endpoints. Can also
       be set with environment variable CO_API_USER. If not specified, you
       will be prompted to enter.
    -p Password for connecting to COmanage Registry API endpoints. Can also
       be set with environment variable CO_API_PASS. If not specified, you
       will be prompted to enter.
    -f First name of a single user to be enrolled.
    -l Last name of a single user to be enrolled.
    -e Email address of a single user to be enrolled.
    -i Input file containing a list of users to be enrolled. Each line
       contains first name, last name, and email address, separated by
       tabs. Overrides -f,-l,-e.
    -o Output file for the newly enrolled users. Defaults to STDOUT.
       Each line contains the email address and ACCESS ID separated by
       tabs.
    -h Print this help message and quit.
```

