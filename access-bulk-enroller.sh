#!/bin/bash

###########################################################################
###########################################################################

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
    -l Last name of a single user to be enrolled.
    -e Email address of a single user to be enrolled.
    -i Input file containing a list of users to be enrolled. Each line
       contains first name, last name, and email address, separated by
       tabs. Overrides -f,-l,-e.
    -o Output file for the newly enrolled users. Defaults to STDOUT.
       Each line contains the email address and ACCESS ID separated by
       tabs.
    -h Print this help message and quit."
exit
}

# Check for required programs (curl, jq)
function check_required_programs {
    local CHECKFAILED=0
    if ! command -v curl &> /dev/null ; then
        echo "Please install the 'curl' program (https://curl.se/)."
        CHECKFAILED=1
    fi
    if ! command -v jq &> /dev/null ; then
        echo "Please install the 'jq' program (https://stedolan.github.io/jq/)."
        CHECKFAILED=1
    else
        # jq version 1.6 or higher is needed for 'base64d'
        JQVERSTR=`jq --version`
        [[ "${JQVERSTR}" =~ jq-([0-9])[.]([0-9]*) ]] && JQMAJ=${BASH_REMATCH[1]} && JQMIN=${BASH_REMATCH[2]}
        if [ "${#JQMAJ}" -eq "0" -o "${#JQMIN}" -eq "0" -o "${JQMAJ}" -lt "1" -o "${JQMIN}" -lt "6" ] ; then
            echo "Please install 'jq' version 1.6 or higher (https://stedolan.github.io/jq/)."
            CHECKFAILED=1
        fi
    fi
    if [ "${CHECKFAILED}" -eq "1" ] ; then
        echo "Exiting."
        exit 1
    fi
}

# Check for command line options, or prompt user for options
function get_command_line_options {
    local OPTIND
    while getopts :s:u:p:f:l:e:i:o:h flag ; do
        case "${flag}" in
            s) server=${OPTARG};;
            u) username=${OPTARG};;
            p) password=${OPTARG};;
            f) firstname=${OPTARG};;
            l) lastname=${OPTARG};;
            e) email=${OPTARG};;
            i) infile=${OPTARG};;
            o) outfile=${OPTARG};;
            h) print_usage
        esac
    done

    # If server not specified, default to CO_API_SERVER or regsitry.access-ci.org
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

    # If infile is not specified, then check for first name, last name, and email
    if [ -z "${infile}" ] ; then
        echo "Adding a single user to ${server}..."
        # Prompt for first name if not passed in
        if [ -z "${firstname}" ] ; then
            until [[ "${firstname}" ]] ; do read -rp 'First name: ' firstname ; done
        fi

        # Prompt for last name if not passed in
        if [ -z "${lastname}" ] ; then
            until [[ "${lastname}" ]] ; do read -rp 'Last name: ' lastname ; done
        fi

        # Prompt for email if not passed in
        if [ -z "${email}" ] ; then
            until [[ "${email}" ]] ; do read -rp 'Email address: ' email ; done
        fi
    fi
}

# Check if there is already an account associated with an email address
# Parameter: email address to check
# Return (echo): ACCESS ID for email address, or empty string if not found
# Usage: existing_access_id=$(check_exising_email "jsmith@gmail.com")
set -E
trap '[ "$?" -ne 99 ] || exit 99' ERR
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

# Print out an email address and the corresponding ACCESS ID
function output_email_and_accessid {
    local email="$1"
    local accessid="$2"
    if [ -n "${outfile}" ] ; then
        if [ "$firstline" == "1" ] ; then
            printf "${email}\t${accessid}\n" >> "${outfile}"
        else
            printf "${email}\t${accessid}\n" > "${outfile}"
        fi
    else
        printf "${email}\t${accessid}\n";
    fi
    firstline="1" # For the first line, overwrite any existing file
}

# Enroll a user, first checking if the email address alread exists
function enroll_user {
    local firstname="$1"
    local lastname="$2"
    local email="$3"
    existing_access_id=$(check_existing_email "${email}")
    if [ -n "${existing_access_id}" ] ; then
        output_email_and_accessid "${email}" "${existing_access_id}"
    else
        echo "No matching ACCESS ID for ${email}"
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
    while read -r LINE ; do
        IFS='	' read -ra params <<<"$LINE"
        enroll_user "${params[0]}" "${params[1]}" "${params[2]}"
    done < "${infile}"
else
    enroll_user "${firstname}" "${lastname}" "${email}"
fi

####################
# END MAIN PROGRAM #
####################
