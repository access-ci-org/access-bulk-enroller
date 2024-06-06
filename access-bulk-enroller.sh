#!/bin/bash

###########################################################################
# This script enrolls new users into an ACCESS CI COmanage Registry.
# Users can be enrolled one-at-a-time or in bulk by reading users from
# a CSV file. The input file contains lines of the following format:
#
#    firstname,middlename,lastname,organization,emailaddress
#
# Middlename can be empty, but all other fields must be present. The
# organization must match an existing organization in the ACCESS database.
# See https://github.com/cilogon/access-bulk-enroller/blob/main/access_orgs.md
# for how to get the current list of organizations.
#
# To see all command line options, use the '-h' switch, e.g.
#
#    bash access-bulk-enroller.sh -h
#
# In particular, notice that the ACCESS COmanage Registry API server
# defaults to registry.access-ci.org (PROD), but can be overridden to use
# either registry-test.access-ci.org (TEST) or registry-dev.access-ci.org
# (DEV). See https://github.com/cilogon/access-bulk-enroller for
# instructions on creating a new API user and associated password which are
# required to run this script.
###########################################################################

# Exit the script even when in a subshell, e.g., $(func ...)
# Taken from https://unix.stackexchange.com/a/48550
set -E
trap '[ "$?" -ne 99 ] || exit 99' ERR

###########################################################################
# Print out usage and exit
###########################################################################
function print_usage {
    >&2 echo "Usage: $0 [options]

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
    -h Print this help message and quit."
    exit 99
}

###########################################################################
# Check for required programs (curl, jq)
###########################################################################
function check_required_programs {
    local CHECKFAILED=0

    if ! command -v curl &> /dev/null ; then
        >&2 echo "ERROR: Please install the 'curl' program (https://curl.se/)."
        CHECKFAILED=1
    fi
    if ! command -v jq &> /dev/null ; then
        >&2 echo "ERROR: Please install the 'jq' program (https://stedolan.github.io/jq/)."
        CHECKFAILED=1
    else
        # jq version 1.6 or higher is needed for advanced functionality
        JQVERSTR=$(jq --version)
        [[ "${JQVERSTR}" =~ jq-([0-9])[.]([0-9]*) ]] && JQMAJ=${BASH_REMATCH[1]} && JQMIN=${BASH_REMATCH[2]}
        if [ "${#JQMAJ}" -eq "0" ] ||
           [ "${#JQMIN}" -eq "0" ] ||
           [ "${JQMAJ}" -lt "1" ] ||
           [ "${JQMIN}" -lt "6" ] ; then
            >&2 echo "ERROR: Please install 'jq' version 1.6 or higher (https://stedolan.github.io/jq/)."
            CHECKFAILED=1
        fi
    fi
    if [ "${CHECKFAILED}" -eq "1" ] ; then
        >&2 echo "Exiting."
        exit 99
    fi
}

###########################################################################
# Check for command line options, or prompt for options.
# All command line options are stored in global variables.
###########################################################################
function get_command_line_options {
    local OPTIND
    local middleopt="0" # Check if '-m' switch was given

    while getopts :s:u:p:f:m:l:g:e:i:o:vh flag ; do
        case "${flag}" in
            s) server=${OPTARG};;
            u) username=${OPTARG};;
            p) password=${OPTARG};;
            f) firstname=${OPTARG};;
            m) middlename=${OPTARG}; middleopt="1";;
            l) lastname=${OPTARG};;
            g) organization=${OPTARG};;
            e) email=${OPTARG};;
            i) infile=${OPTARG};;
            o) outfile=${OPTARG};;
            v) verbose="1";;
            h) print_usage;;
            *) print_usage;;
        esac
    done

    # If no server specified, default to CO_API_SERVER or regsitry.access-ci.org
    if [ -z "${server}" ] ; then
        server="${CO_API_SERVER}"
    fi
    if [ -z "${server}" ] ; then
        server='registry.access-ci.org'
    fi

    # If username and password not specified, look in environment
    if [ -z "${username}" ] ; then
        username="${CO_API_USER}"
    fi
    if [ -z "${password}" ] ; then
        password="${CO_API_PASS}"
    fi

    # If username and password still not set, prompt for them
    if [ -z "${username}" ] ; then
        until [[ "${username}" ]] ; do read -rp 'COmanage API username: ' username ; done
    fi
    if [ -z "${password}" ] ; then
        until [[ "${password}" ]] ; do read -srp 'COmanage API password: ' password ; done
        echo # Output CR-LF after hidden password
    fi

    # If no infile specified, then check for first, middle, and last name,
    # organization, and email
    if [ -z "${infile}" ] ; then
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: Adding a single user to ${server}..."
        fi
        # Prompt for first name if not passed in
        if [ -z "${firstname}" ] ; then
            until [[ "${firstname}" ]] ; do read -rp 'First name: ' firstname ; done
        fi

        # Prompt for middle name (may be blank)
        if [ -z "${middlename}" ] && [ "${middleopt}" == "0" ] ; then
            read -rp 'Middle name: ' middlename
        fi

        # Prompt for last name if not passed in
        if [ -z "${lastname}" ] ; then
            until [[ "${lastname}" ]] ; do read -rp 'Last name: ' lastname ; done
        fi

        # Prompt for organization if not passed in
        if [ -z "${organization}" ] ; then
            until [[ "${organization}" ]] ; do read -rp 'Organization: ' organization ; done
        fi

        # Prompt for email if not passed in
        if [ -z "${email}" ] ; then
            until [[ "${email}" ]] ; do read -rp 'Email address: ' email ; done
        fi
    fi

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: API server   = ${server}"
        >&2 echo "INFO: API username = ${username}"
        if [ -n "${firstname}" ] ; then
            >&2 echo "INFO: firstname    = ${firstname}"
        fi
        if [ -n "${middlename}" ] ; then
            >&2 echo "INFO: middlename   = ${middlename}"
        fi
        if [ -n "${lastname}" ] ; then
            >&2 echo "INFO: lastname     = ${lastname}"
        fi
        if [ -n "${organization}" ] ; then
            >&2 echo "INFO: organization = ${organization}"
        fi
        if [ -n "${email}" ] ; then
            >&2 echo "INFO: email        = ${email}"
        fi
        if [ -n "${infile}" ] ; then
            >&2 echo "INFO: infile       = ${infile}"
        fi
        if [ -n "${outfile}" ] ; then
            >&2 echo "INFO: outfile      = ${outfile}"
        fi
    fi
}

###########################################################################
# Make a curl call to a COmange Registry API endpoint and return the body
# and response_code in variable references in the 1st and 2nd parameter.
# Parameters:
#    body - a reference to the body of the response to return
#    response_code - a reference to the HTTP code to return
#    url_path - the url path to append to https://<server>/registry/
#    data (optional) - JSON data to be POSTed to the API endpoint
# Usage:
#    body=''
#    response_code=''
#    curl_call_registry body response_code <API_ENDPOINT_URL> <JSON_DATA>
# Note that JSON_DATA is optional
###########################################################################
function curl_call_registry {
    local -n body_ref="$1"
    local -n response_code_ref="$2"
    local url_path="$3"
    local data="$4"

    local usedata=()
    if [ -n "${data}" ] ; then
        usedata=(-X POST -H 'Content-Type: application/json' -d "${data}")
    fi

    response=$(curl -s -w "%{http_code}" \
        -u "${username}:${password}" \
        "${usedata[@]}" \
        "https://${server}/registry/${url_path}")

    # shellcheck disable=SC2034
    body_ref="${response::-3}"
    # shellcheck disable=SC2034
    response_code_ref="${response: -3:3}"
}

###########################################################################
# Return the COPersonIdentifier associated with an email address, or
# empty string if not found
# Parameter: email address to check
# Return (echo): CoPersonId for email address, or empty string if not found
# Usage: co_person_id=$(get_co_person_id_for_email "jsmith@gmail.com")
###########################################################################
function get_co_person_id_for_email {
    local email="$1"
    local encodedemail
    encodedemail=$(jq -rn --arg x "${email}" '$x|@uri')

    local body
    local response_code
    curl_call_registry body response_code \
        "co_people.json?coid=2&search.mail=${encodedemail}"

    local email_count
    email_count=$(echo "${body}" | jq '.CoPeople | length')
    if [ -z "${email_count}" ] ; then
        >&2 echo 'ERROR: Unable to search for email address. Exiting.'
        exit 99
    fi

    if [ "${email_count}" -gt "0" ] ; then
        echo "${body}" | jq -r '.CoPeople[0].Id'
    else
        echo
    fi
}

###########################################################################
# Return the ACCESS CI associated with an email address, or empty string
# if not found
# Parameter: email address to check
# Return (echo): ACCESS ID for email address, or empty string if not found
# Usage: accessid=$(get_access_id_for_email "jsmith@gmail.com")
###########################################################################
function get_access_id_for_email {
    local email="$1"

    local co_person_id
    co_person_id=$(get_co_person_id_for_email "${email}")
    if [ -n "${co_person_id}" ] ; then
        local body
        local response_code
        curl_call_registry body response_code \
            "identifiers.json?copersonid=${co_person_id}"
        echo "${body}" | jq -r '.Identifiers[] | select(.Type=="accessid").Identifier'
    else
        echo
    fi
}

###########################################################################
# Helper function to print full user info for a given ACCESSID
# Parameter: accessid - the ACCESS ID to search for
###########################################################################
function get_user_info {
    local accessid="$1"

    local body
    local response_code
    curl_call_registry body response_code \
        "api/co/2/core/v1/people/${accessid}"
    >&2 echo "${body}"
}

###########################################################################
# Return the ID of the first active Terms and Conditions element.
# You should only call this once since it's the same for all users.
###########################################################################
function get_active_tandc_id {
    local body
    local response_code
    curl_call_registry body response_code \
        "co_terms_and_conditions.json?coid=2"
    echo "${body}" | jq -r '.CoTermsAndConditions[] | select(.Status=="Active") | .Id' | head -1
}

###########################################################################
# Check a curl response code against a desired HTTP code (e.g., "201").
# If no match, exit the script with an error message.
# Parameters:
#    response_code - the HTTP code returned from curl
#    desired_code - the "successful" HTTP code, e.g., "201"
#    error_msg - a message to print if the response code doesn't match
###########################################################################
function check_response_code {
    local response_code="$1"
    local desired_code="$2"
    local error_msg="$3"

    if [ "${response_code}" != "${desired_code}" ] ; then
        >&2 echo "ERROR: ${error_msg} Exiting."
        exit 99
    fi
}

###########################################################################
# Create a new ACCESS user by calling the Core API. Exit on failure.
# Parameters:
#    firstname - first name of the user
#    middlename - middle name of the user (can be empty string)
#    lastname - last name of the user
#    organization - organization/university of the user
#    email - email of the user
#    accessid - ACCESS ID of the user
###########################################################################
function create_new_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"

    # If middlename is empty, set it to 'null'. Otherwise, quote it.
    if [ -z "${middlename}" ] ; then
        middlename='null'
    else
        middlename='"'"${middlename}"'"'
    fi

    local new_user_json
    new_user_json=$(cat <<-END
	{
		"CoPerson": {
			"co_id": "2",
			"status": "A",
			"date_of_birth": null,
			"timezone": null
		},
		"CoGroupMember": [
			{
				"co_group_id": "5",
				"member": true,
				"owner": false,
				"valid_from": null,
				"valid_through": null,
				"co_group_nesting_id": null
			},
			{
				"co_group_id": "6",
				"member": true,
				"owner": false,
				"valid_from": null,
				"valid_through": null,
				"co_group_nesting_id": null
			}
		],
		"EmailAddress": [
			{
				"mail": "${email}",
				"description": null,
				"type": "official",
				"verified": true
			}
		],
		"CoPersonRole": [
			{
				"sponsor_co_person_id": null,
				"cou_id": null,
				"affiliation": "affiliate",
				"title": null,
				"o": "${organization}",
				"ou": null,
				"valid_from": null,
				"valid_through": null,
				"ordr": null,
				"status": "A",
				"manager_co_person_id": null,
				"Address": [],
				"AdHocAttribute": [],
				"TelephoneNumber": []
			}
		],
		"Name": [
			{
				"honorific": null,
				"given": "${firstname}",
				"middle": ${middlename},
				"family": "${lastname}",
				"suffix": null,
				"type": "official",
				"language": null,
				"primary_name": true
			}
		],
		"Url": [],
		"Krb": [],
		"SshKey": []
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating new ACCESS user account for ${email}."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "api/co/2/core/v1/people" "${new_user_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create new ACCESS user for ${email}."
}

###########################################################################
# Create a new Organizational Identity for the user. Return the OrgId ID.
# Exit on failure.
# Return (echo): The ID for the newly created Organizational Identity.
# Usage: org_identity_id=$(create_new_org_identity)
###########################################################################
function create_new_org_identity {
    local new_org_identity_json
    new_org_identity_json=$(cat <<-END
	{
		"RequestType":"OrgIdentities",
		"Version":"1.0",
		"OrgIdentities":
		[
			{
				"Version":"1.0",
				"Affiliation": null,
				"Title": null,
				"O": null,
				"Ou": null,
				"CoId": "2",
				"ValidFrom": null,
				"ValidThrough": null,
				"DateOfBirth": null
			}
		]
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating new Organizational Identity."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "org_identities.json" "${new_org_identity_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create new Organizational Identity."

    echo "${body}" | jq -r '.Id'
}

###########################################################################
# Create a new link between the CoPerson record and the Organizational
# Identity record.
# Parameters:
#    co_person_id - the ID of the CoPerson record
#    org_identity_id - the ID of the Organizational Identity record
###########################################################################
function create_new_link {
    local co_person_id="$1"
    local org_identity_id="$2"

    local new_link_json
    new_link_json=$(cat <<-END
	{
		"RequestType":"CoOrgIdentityLinks",
		"Version":"1.0",
		"CoOrgIdentityLinks":
		[
			{
				"Version": "1.0",
				"CoPersonId": "${co_person_id}",
				"OrgIdentityId": "${org_identity_id}"
			}
		]
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating link between CoPerson ${co_person_id} and OrgId ${org_identity_id}."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "co_org_identity_links.json" "${new_link_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create link between CoPerson ${co_person_id} and OrgId ${org_identity_id}."
}

###########################################################################
# Create a new Name object to add to the Organizational Identity record.
# Parameters:
#    firstname - first name of the user
#    middlename - middle name of the user (can be empty string)
#    lastname - last name of the user
#    org_identity_id - the ID of the Organizational Identity record
###########################################################################
function create_new_name {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local org_identity_id="$4"

    # If middlename is empty, set it to 'null'. Otherwise, quote it.
    if [ -z "${middlename}" ] ; then
        middlename='null'
    else
        middlename='"'"${middlename}"'"'
    fi

    local new_name_json
    new_name_json=$(cat <<-END
	{
		"RequestType":"Names",
		"Version":"1.0",
		"Names":
		[
			{
				"Version": "1.0",
				"Honorific": null,
				"Given": "${firstname}",
				"Middle": ${middlename},
				"Family": "${lastname}",
				"Suffix": null,
				"Type": "official",
				"Language": "",
				"PrimaryName": true,
				"Person":
				{
					"Type": "Org",
					"Id": "${org_identity_id}"
				}
			}
		]
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating new Name for OrgId ${org_identity_id}."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "names.json" "${new_name_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create a new Name for ${firstname} ${lastname}."
}

###########################################################################
# Create a new Identity object of type ePPN to add to the Organizational
# Identity record.
# Parameters:
#    accessid - ACCESS ID of the user
#    org_identity_id - the ID of the Organizational Identity record
###########################################################################
function create_new_identifier {
    local accessid="$1"
    local org_identity_id="$2"

    local new_identifier_json
    new_identifier_json=$(cat <<-END
	{
		"RequestType":"Identifiers",
		"Version":"1.0",
		"Identifiers":
		[
			{
				"Version": "1.0",
				"Type": "eppn",
				"Identifier": "${accessid}@access-ci.org",
				"Login": true,
				"Person":{"Type":"Org","Id":"${org_identity_id}"},
				"Status": "Active"
			}
		]
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating new Identifier ${accessid}@access-id.org for OrgId ${org_identity_id}."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "identifiers.json" "${new_identifier_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create a new Identifier for ${accessid}."
}

###########################################################################
# Create new Terms & Conditions Agreement for the CoPerson record.
# Parameters:
#    co_tandc_id - The ID of the active Terms & Conditions
#    co_person_id - The ID of the CoPerson record
###########################################################################
function create_new_tandc {
    local co_tandc_id="$1"
    local co_person_id="$2"

    local new_tandc_json
    new_tandc_json=$(cat <<-END
	{
		"RequestType":"CoTAndCAgreements",
		"Version":"1.0",
		"CoTAndCAgreements":
		[
			{
				"Version": "1.0",
				"CoTermsAndConditionsId": "${co_tandc_id}",
				"Person": {
					"Type":"CO",
					"Id":"${co_person_id}"
				}
			}
		]
	}
END
)

    if [ -n "${verbose}" ] ; then
        >&2 echo "INFO: Creating new Terms & Conditions Agreement for ${co_person_id}."
    fi

    local body
    local response_code
    curl_call_registry body response_code \
        "co_t_and_c_agreements.json" "${new_tandc_json}"
    check_response_code "${response_code}" "201" \
        "Unable to create a new Terms & Conditions Agreement for CoPerson ${co_person_id}."
}

###########################################################################
# Output original user parameters and the corresponding ACCESS ID.
# Print to $outfile (global variable) if given, or STDOUT otherwise.
# Parameters:
#    firstname - first name of the user
#    middlename - middle name of the user (can be empty string)
#    lastname - last name of the user
#    organization - organization/university of the user
#    email - email of the user
#    accessid - ACCESS ID of the user
###########################################################################
function output_access_id_for_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"
    local accessid="$6"

    if [ -n "${outfile}" ] ; then
        if [ -n "${firstline}" ] ; then # Append to file after first line
            printf "%s,%s,%s,%s,%s,%s\n" \
                "${firstname}" "${middlename}" "${lastname}" \
                "${organization}" "${email}" "${accessid}" >> "${outfile}"
        else # Overwrite any existing file for the first line
            printf "%s,%s,%s,%s,%s,%s\n" \
                "${firstname}" "${middlename}" "${lastname}" \
                "${organization}" "${email}" "${accessid}" > "${outfile}"
        fi
    else # Print to STDOUT
        printf "%s,%s,%s,%s,%s,%s\n" \
            "${firstname}" "${middlename}" "${lastname}" \
            "${organization}" "${email}" "${accessid}"
    fi
    firstline="1" # For the first line only, overwrite any existing file
}

###########################################################################
# Enroll a user, checking first if the email address alread exists.
# Calls output_access_id_for_user to print out the resulting ACCESS ID.
# Parameters:
#    firstname - first name of the user
#    middlename - middle name of the user (can be empty string)
#    lastname - last name of the user
#    organization - organization/university of the user
#    email - email of the user
###########################################################################
function enroll_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"

    local accessid
    accessid=$(get_access_id_for_email "${email}")
    if [ -n "${accessid}" ] ; then
        # There is already an ACCESS ID for the email, so print it out
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: Found existing account for ${email}: ${accessid}"
        fi
        output_access_id_for_user \
            "${firstname}" "${middlename}" "${lastname}" \
            "${organization}" "${email}" "${accessid}"
        # Uncomment to see the JSON of the CoPerson record for the user
        # get_user_info "${accessid}"
    else
        # Create a new user entry
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: No matching ACCESS ID for ${email}. Adding new user."
        fi

        create_new_user "${firstname}" "${middlename}" "${lastname}" \
            "${organization}" "${email}"

        local co_person_id
        co_person_id=$(get_co_person_id_for_email "${email}")
        accessid=$(get_access_id_for_email "${email}")
        if [ -z "${co_person_id}" ] || [ -z "${accessid}" ] ; then
            >&2 echo "ERROR: Successfully created new account, but unable to find CoPerson ID or ACCESS ID for ${email}. Exiting."
            exit 99
        fi

        local org_identity_id
        org_identity_id=$(create_new_org_identity)

        create_new_link "${co_person_id}" "${org_identity_id}"

        create_new_name "${firstname}" "${middlename}" "${lastname}" \
            "${org_identity_id}"

        create_new_identifier "${accessid}" "${org_identity_id}"

        if [ -n "${tandc_id}" ] ; then
            create_new_tandc "${tandc_id}" "${co_person_id}"
        fi

        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: Success! Created new ACCESS ID ${accessid}."
        fi
        output_access_id_for_user \
            "${firstname}" "${middlename}" "${lastname}" \
            "${organization}" "${email}" "${accessid}"
    fi
}

######################
# BEGIN MAIN PROGRAM #
######################

check_required_programs
get_command_line_options "$@"

# Get the Id of the active Terms & Conditions - empty string if none
tandc_id=$(get_active_tandc_id)
if [ -z "${tandc_id}" ] && [ -n "${verbose}" ] ; then
    >&2 echo "WARN: Unable to find an active Terms & Conditions."
fi

if [ -n "${infile}" ] ; then
    # Read in CSV file to enroll multiple users
    linecount=1
    while read -r LINE ; do
        # Split line on commas
        IFS=',' read -ra params <<<"${LINE}"
        # Sanity check - make sure all paramters are present
        # Note that middle name (params[1]) may be blank
        if [ -n "${params[0]}" ] &&
           [ -n "${params[2]}" ] &&
           [ -n "${params[3]}" ] &&
           [ -n "${params[4]}" ] ; then
            enroll_user "${params[0]}" "${params[1]}" "${params[2]}" \
                "${params[3]}" "${params[4]}"
        else
            if [ -n "${verbose}" ] ; then
                >&2 echo "WARN: Parameter(s) missing on line ${linecount}. Skipping."
            fi
        fi
        linecount=$((linecount+1))
    done < "${infile}"
else
    # Enroll a single user using values read from command line
    enroll_user "${firstname}" "${middlename}" "${lastname}" \
        "${organization}" "${email}"
fi

####################
# END MAIN PROGRAM #
####################
