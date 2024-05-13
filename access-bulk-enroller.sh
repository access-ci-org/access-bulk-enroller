#!/bin/bash

###########################################################################
###########################################################################


# Exit the script when in a sub-shell, e.g., $(...). Taken from:
# https://unix.stackexchange.com/a/48550
set -E
trap '[ "$?" -ne 99 ] || exit 99' ERR

# Print out usage
function print_usage {
    echo "Usage: $0 [options]

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
    -m Middle name of a single user to be enrolled. May be emtpy.
    -l Last name of a single user to be enrolled.
    -g Organization of a single user to be enrolled.
    -e Email address of a single user to be enrolled.
    -i Input file containing a list of users to be enrolled. Each line
       contains first name, last name, and email address, separated by
       tabs. Overrides -f,-l,-e.
    -o Output file for the newly enrolled users. Defaults to STDOUT.
       Each line contains the email address and ACCESS ID separated by
       tabs.
    -v Print additional informational and warning messages to STDERR.
    -h Print this help message and quit."
exit
}

# Check for required programs (curl, jq)
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
        # jq version 1.6 or higher is needed for 'base64d'
        JQVERSTR=`jq --version`
        [[ "${JQVERSTR}" =~ jq-([0-9])[.]([0-9]*) ]] && JQMAJ=${BASH_REMATCH[1]} && JQMIN=${BASH_REMATCH[2]}
        if [ "${#JQMAJ}" -eq "0" -o "${#JQMIN}" -eq "0" -o "${JQMAJ}" -lt "1" -o "${JQMIN}" -lt "6" ] ; then
            >&2 echo "ERROR: Please install 'jq' version 1.6 or higher (https://stedolan.github.io/jq/)."
            CHECKFAILED=1
        fi
    fi
    if [ "${CHECKFAILED}" -eq "1" ] ; then
        >&2 echo "Exiting."
        exit 1
    fi
}

# Check for command line options, or prompt user for options
function get_command_line_options {
    local OPTIND
    local middleopt="0"
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
        echo
    fi

    # If no infile specified, then check for first name, last name,
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
        if [ -z "${middlename}" -a "${middleopt}" == "0" ] ; then
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

# Return the COPersonIdentifier associated with an email address, or
# '' if not found
# Parameter: email address to check
# Return (echo): CoPersonId for email address, or empty string if not found
# Usage: co_person_id=$(get_co_person_id_for_email "jsmith@gmail.com")
function get_co_person_id_for_email {
    local email="$1"
    local encodedemail=`jq -rn --arg x ${email} '$x|@uri'`
    local response=$(curl -s -u "${username}:${password}" "https://${server}/registry/co_people.json?coid=2&search.mail=${encodedemail}")
    local email_count=$(echo "${response}" | jq '.CoPeople | length')

    if [ $? -ne 0 -o -z "${email_count}" ] ; then
        >&2 echo 'ERROR: Search for email address failed. Exiting.'
        exit 99
    fi

    if [ $email_count -gt 0 ] ; then
        echo ${response} | jq -r '.CoPeople[0].Id'
    else
        echo ''
    fi
}

# Return the ACCESS CI associated with an email address, or '' if not found
# Parameter: email address to check
# Return (echo): ACCESS ID for email address, or empty string if not found
# Usage: access_id=$(get_access_id_for_email "jsmith@gmail.com")
function get_access_id_for_email {
    local email="$1"
    local co_person_id=$(get_co_person_id_for_email "${email}")

    if [ -n "${co_person_id}" ] ; then
        response=$(curl -s -u "${username}:${password}" "https://${server}/registry/identifiers.json?copersonid=${co_person_id}")
        echo "${response}" | jq -r '.Identifiers[] | select(.Type=="accessid").Identifier'
    else
        echo ''
    fi
}

# Print out user parameters and the corresponding ACCESS ID
function output_access_id_for_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"
    local accessid="$6"
    if [ -n "${outfile}" ] ; then
        if [ -n "${firstline}" ] ; then
            printf "${firstname},${middlename},${lastname},${organization},${email},${accessid}\n" >> "${outfile}"
        else
            printf "${firstname},${middlename},${lastname},${organization},${email},${accessid}\n" > "${outfile}"
        fi
    else
        printf "${firstname},${middlename},${lastname},${organization},${email},${accessid}\n";
    fi
    firstline="1" # For the first line, overwrite any existing file
}

# Temporary function to print out info for a given accessid
function get_user_info {
    local accessid="$1"
    local response=$(curl -s -u "${username}:${password}" "https://${server}/registry/api/co/2/core/v1/people/${accessid}")
    >&2 echo "${response}"
}

# Return the ID of the first Active Terms and Conditions element
function get_active_tandc_id {
    local response=$(curl -s -u "${username}:${password}" "https://${server}/registry/co_terms_and_conditions.json?coid=2")
    echo "${response}" | jq -r '.CoTermsAndConditions[] | select(.Status=="Active") | .Id'
}

# Get the JSON statement to create a new user. 
# Note: make sure to use TAB characters at the beginning of the lines
# in the JSON blob below.
function get_new_user_json {
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
    cat <<-EOF
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
		"OrgIdentity": [
			{
				"status": null,
				"date_of_birth": null,
				"affiliation": null,
				"title": null,
				"o": null,
				"ou": null,
				"co_id": "2",
				"valid_from": null,
				"valid_through": null,
				"manager_identifier": null,
				"sponsor_identifier": null,
				"Address": [],
				"AdHocAttribute": [],
				"EmailAddress": [],
                "Identifier": [],
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
				"TelephoneNumber": [],
				"Url": []
			}
		],
		"Krb": [],
		"SshKey": []
	}
EOF
}

#
function get_new_orgidentity_json {
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
    cat <<-EOF
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
EOF
}

#
function get_link_json {
    local co_person_id="$1"
    local org_identity_id="$2"
    cat <<-EOF
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
EOF
}

function get_new_name_json {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local co_org_identity_id="$4"
    # If middlename is empty, set it to 'null'. Otherwise, quote it.
    if [ -z "${middlename}" ] ; then
        middlename='null'
    else
        middlename='"'"${middlename}"'"'
    fi
    cat <<-EOF
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
					"Id": "${co_org_identity_id}"
				}
			}
		]
	}
EOF
}

#
function get_new_identifier_json {
    local access_id="$1"
    local co_org_identity_id="$2"
    cat <<-EOF
	{
		"RequestType":"Identifiers",
		"Version":"1.0",
		"Identifiers":
		[
			{
				"Version": "1.0",
				"Type": "eppn",
				"Identifier": "${access_id}@access-ci.org",
				"Login": true,
				"Person":{"Type":"Org","Id":"${co_org_identity_id}"},
				"Status": "Active"
			}
		]
	}
EOF
}

#
function get_new_tandc_json {
	local co_tandc_id="$1"
    local co_person_id="$2"
    cat <<-EOF
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
EOF
}

# Enroll a user, first checking if the email address alread exists
function enroll_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"
    local access_id=$(get_access_id_for_email "${email}")
    if [ -n "${access_id}" ] ; then
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: Found existing account for ${email}: ${access_id}"
        fi
        output_access_id_for_user "${firstname}" "${middlename}" "${lastname}" "${organization}" "${email}" "${access_id}"
        get_user_info "${access_id}"
    else
        # Probabbly remove/move this echo
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: No matching ACCESS ID for ${email}. Adding new user."
        fi
        # This is where we actually add a new user 
        # Maybe move to another function???
        local newuserjson=$(get_new_user_json "${firstname}" "${middlename}" "${lastname}" "${organization}" "${email}")
        #echo "${newuserjson}"
        local response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${newuserjson}" "https://${server}/registry/api/co/2/core/v1/people")
        local body="${response::-3}"
        local response_code="${response: -3:3}"
        echo "body for new user = ${body}"
        echo "response_code = ${response_code}"
        if [ "${response_code}" == "201" ] ; then
            # Successful creation of account. Get the co_person_id and access_id
            local co_person_id=$(get_co_person_id_for_email "${email}")
            access_id=$(get_access_id_for_email "${email}")
            if [ -n "${co_person_id}" -a -n "${access_id}" ] ; then
                >&2 echo "Creating OrgIdentity"
                local neworgidjson=$(get_new_orgidentity_json "${firstname}" "${middlename}" "${lastname}" "${organization}" "${email}")
                response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${neworgidjson}" "https://${server}/registry/org_identities.json")
                body="${response::-3}"
                response_code="${response: -3:3}"
                echo "body of new org_identities = ${body}"
                echo "response_code = ${response_code}"

                local co_org_identity_id=$(echo "${body}" | jq -r '.Id')
                echo "co_org_identity_id = ${co_org_identity_id}"
                # Link the orgid with the co_persion_id
                local newlinkjson=$(get_link_json "${co_person_id}" "${co_org_identity_id}")
                response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${newlinkjson}" "https://${server}/registry/co_org_identity_links.json")
                body="${response::-3}"
                response_code="${response: -3:3}"
                echo "body of linking = ${body}"
                echo "response_code = ${response_code}"

                # Create a new Name for the OrgId
                local newnamejson=$(get_new_name_json "${firstname}" "${middlename}" "${lastname}" "${co_org_identity_id}")
                response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${newnamejson}" "https://${server}/registry/names.json")
                body="${response::-3}"
                response_code="${response: -3:3}"
                echo "body of new name = ${body}"
                echo "response_code = ${response_code}"

                # Create a new Identifier for the OrgId
                local newidentifierjson=$(get_new_identifier_json "${access_id}" "${co_org_identity_id}")
                response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${newidentifierjson}" "https://${server}/registry/identifiers.json")
                body="${response::-3}"
                response_code="${response: -3:3}"
                echo "body of new identifier = ${body}"
                echo "response_code = ${response_code}"

                # Create a new Terms & Conditions Agreement
                if [ -n "${tandc_id}" ] ; then
                    local newtandcjson=$(get_new_tandc_json "${tandc_id}" "${co_person_id}")
                    response=$(curl -s -w "%{http_code}" -u "${username}:${password}" -X POST -H 'Content-Type: application/json' -d "${newtandcjson}" "https://${server}/registry/co_t_and_c_agreements.json")
                    body="${response::-3}"
                    response_code="${response: -3:3}"
                    echo "body of new tandc agreement = ${body}"
                    echo "response_code = ${response_code}"
                fi

            else
                >&2 "ERROR: Successfully created new account, but unable to find ACCESS ID. Exiting."
                exit
            fi
        fi
    fi
}

######################
# BEGIN MAIN PROGRAM #
######################

check_required_programs
get_command_line_options "$@"

tandc_id=$(get_active_tandc_id)

if [ -n "${infile}" ] ; then
    linecount=1;
    while read -r LINE ; do
        IFS=',' read -ra params <<<"${LINE}"
        # Sanity check - make sure all paramters are present
        # Note that middle name (params[1]) may be blank
        if [ -n "${params[0]}" -a -n "${params[2]}" -a -n "${params[3]}" -a -n "${params[4]}" ] ; then
            enroll_user "${params[0]}" "${params[1]}" "${params[2]}" "${params[3]}" "${params[4]}"
        else
            if [ -n "${verbose}" ] ; then
                >&2 echo "ERROR: Parameter(s) missing on line ${linecount}. Skipping."
            fi
        fi
        linecount=$((linecount+1))
    done < "${infile}"
else
    enroll_user "${firstname}" "${middlename}" "${lastname}" "${organization}" "${email}"
fi

####################
# END MAIN PROGRAM #
####################
