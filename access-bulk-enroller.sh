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
    while getopts :s:u:p:f:m:l:g:e:i:o:vh flag ; do
        case "${flag}" in
            s) server=${OPTARG};;
            u) username=${OPTARG};;
            p) password=${OPTARG};;
            f) firstname=${OPTARG};;
            m) middlename={$OPTARG};;
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
        if [ -z "${middlename}" ] ; then
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

# Check if there is already an account associated with an email address
# Parameter: email address to check
# Return (echo): ACCESS ID for email address, or empty string if not found
# Usage: existing_access_id=$(check_exising_email "jsmith@gmail.com")
function check_existing_email {
    local email="$1"
    local encodedemail=`jq -rn --arg x ${email} '$x|@uri'`
    local response=$(curl -s -u "${username}:${password}" "https://${server}/registry/co_people.json?coid=2&search.mail=${encodedemail}")
    local email_count=$(echo "${response}" | jq '.CoPeople | length')

    if [ $? -ne 0 -o -z "${email_count}" ] ; then
        >&2 echo 'ERROR: Curl call for checking email address failed. Exiting.'
        exit 99
    fi

    if [ $email_count -gt 0 ] ; then
        match_user=$(echo ${response} | jq -r '.CoPeople[0].Id')
        response=$(curl -s -u "${username}:${password}" "https://registry-dev.access-ci.org/registry/identifiers.json?copersonid=${match_user}")
        echo "${response}" | jq -r '.Identifiers[] | select(.Type=="accessid").Identifier'
    else
        echo ''
    fi
}

# Print out user parameters and the corresponding ACCESS ID
function output_accessid_for_user {
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

function get_user_info {
    local accessid="$1"
    local response=$(curl -s -u "${username}:${password}" "https://${server}/registry/api/co/2/core/v1/people/${accessid}")
    >&2 echo "${response}"
}

# Enroll a user, first checking if the email address alread exists
function enroll_user {
    local firstname="$1"
    local middlename="$2"
    local lastname="$3"
    local organization="$4"
    local email="$5"
    existing_access_id=$(check_existing_email "${email}")
    if [ -n "${existing_access_id}" ] ; then
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: Found existing account for ${email}: ${existing_access_id}"
        fi
        output_accessid_for_user "${firstname}" "${middlename}" "${lastname}" "${organization}" "${email}" "${existing_access_id}"
        get_user_info "${existing_access_id}"
    else
        # Probabbly replace this echo with a different message
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: No matching ACCESS ID for ${email}. Adding new user."
        fi
        # TODO: This is were we actually add a new user 
        #       Probably another function
    fi
}

######################
# BEGIN MAIN PROGRAM #
######################

check_required_programs
get_command_line_options "$@"


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
