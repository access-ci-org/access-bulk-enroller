#!/bin/bash

###########################################################################
# This script reads in a CSV file of users to be bulk-enrolled into an
# ACCESS COmanage Registry and validates all lines. Validation includes:
#
# 1. The input CSV file contains lines of the following format:
#    firstname,middlename,lastname,organization,emailaddress
#    Middlename can be empty, but all other fields must be present.
# 2. The lastname is at least 2 characters long.
# 3. The organization matches an organization in the ACCESS database. See
#    https://github.com/cilogon/access-bulk-enroller/blob/main/access_orgs.md
#    for how to get the current list of ACCESS organizations.
# 4. The email address format is valid and has a domain with an MX record.
#
# To see all command line options, use the '-h' switch, e.g.
#
#    bash validate-csv.sh -h
#
# By default, the input CSV file is assumed to be named
# "bulk-enrollment.csv" in the current directory. The list of ACCESS
# Organizations is assumed to be named "access_orgs.txt" also in the
# current directory. Both of these default values can be overridden via
# command line switches.
#
# If the access_orgs.txt file is not found, it will be downloaded
# automatically from GitHub and placed in the current directory.
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
    -h Print this help message and quit."
    exit 99
}

###########################################################################
# Check for required programs (curl, dig)
###########################################################################
function check_required_programs {
    local CHECKFAILED=0

    for app in curl dig ; do
        if ! command -v "${app}" &> /dev/null ; then
            >&2 echo "ERROR: Please install the '${app}' program."
            CHECKFAILED=1
        fi
    done

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

    while getopts :i:g:o:vh flag ; do
        case "${flag}" in
            i) infile=${OPTARG};;
            g) orgfile=${OPTARG};;
            o) outfile=${OPTARG};;
            v) verbose="1";;
            h) print_usage;;
            *) print_usage;;
        esac
    done

    # If no infile specified, use bulk-enrollment.csv .
    if [ -z "${infile}" ] ; then
        infile='bulk-enrollment.csv'
    fi
    # If infile not found, prompt for infile until found.
    if [ ! -r "${infile}" ] ; then
        until [[ -r "${infile}" ]] ; do read -rp 'CSV file to validate: ' infile ; done
    fi

    # If no orgfile is specified, use access_orgs.txt .
    if [ -z "${orgfile}" ] ; then
        orgfile='access_orgs.txt'
    fi
    # If orgfile is not found, download it from GitHub.
    if [ ! -r "${orgfile}" ] ; then
        if [ -n "${verbose}" ] ; then
            >&2 echo "INFO: ACCESS Organization file not found. Downloading..."
        fi
        curl -s "https://raw.githubusercontent.com/access-ci-org/access-bulk-enroller/main/access_orgs.txt" --output "access_orgs.txt"
    fi
}

###########################################################################
# Output a line to the outfile or to STDOUT
# Parameters:
#    line - the line to be printed to outfile or STDOUT
#    lineno - (optional) line number to prepend to the output line
###########################################################################
function output_line {
    local line="$1"
    local lineno="$2"

    linestr=""
    if [ ${#lineno} -gt "0" ] ; then
        linestr="Line ${lineno}:"
    fi

    if [ -n "${outfile}" ] ; then
        if [ -n "${firstline}" ] ; then # Append to file after first line
            printf "%s%s\n" "${linestr}" "${line}" >> "${outfile}"
        else # Overwrite any existing file for the first line
            printf "%s%s\n" "${linestr}" "${line}" > "${outfile}"
        fi
    else # Print to STDOUT
        if [ -n "${verbose}" ] ; then
            >&2 echo
        fi
        printf "%s%s\n" "${linestr}" "${line}"
    fi
    firstline="1" # For the first line only, overwrite any existing file
}


######################
# BEGIN MAIN PROGRAM #
######################

check_required_programs
get_command_line_options "$@"

if [ -r "${infile}" ] && [ -r "${orgfile}" ] ; then
    # Read in the ACCESS Organization file into an associative array where
    # the keys of the array are the organizations and the values are "1".
    declare -A orgarray
    while read -r LINE ; do
       orgarray["${LINE}"]="1"
    done < "${orgfile}"

    linecount=1
    totallines=$(wc -l "${infile}" | awk '{print $1}')
    founderror=0

    while read -r LINE ; do
        # Verbose - print progress status of "Line #/##"
        if [ -n "${verbose}" ] ; then
            >&2 echo -ne "\rLine ${linecount}/${totallines}"
        fi

        # Split line on commas; params[] contains names, email, org
        IFS=',' read -ra params <<<"${LINE}"

        # First, make sure all paramters are present
        # Note that middle name (params[1]) may be blank
        if [ -z "${params[0]}" ] ||
           [ -z "${params[2]}" ] ||
           [ -z "${params[3]}" ] ||
           [ -z "${params[4]}" ] ; then
            founderror=1
            output_line "Parameter(s) missing." "${linecount}"
        fi

        # Next, check if the last name is 2 characters or longer
        lastnamelen=$(expr "${params[2]}" : '.*')
        if [ "${lastnamelen}" -lt "2" ] ; then
            output_line "Last name '${params[2]}' is too short." "${linecount}"
        fi

        # Next, check if the organization is in the orgfile
        if [ "${orgarray["${params[3]}"]}" != "1" ] ; then
            founderror=1
            output_line "'${params[3]}' is not a valid Organization." "${linecount}"
        fi

        # Finally, check if the email address is valid format
        # Gleaned from https://stackoverflow.com/a/2138835/12381604
        IFS='@' read -ra emailparts <<<"${params[4]}"
        if [ "${#emailparts[@]}" -ne "2" ] ; then
            founderror=1
            output_line "'${params[4]}' is not a valid email address." "${linecount}"
        fi

        # Check if the email domain has an MX record
        domainokay=$(dig +short mx "${emailparts[1]}" 2>/dev/null | wc -l)
        if [ "${domainokay}" -eq "0" ] ; then
            founderror=1
            output_line " Domain for email address '${params[4]}' is not valid." "${linecount}"
        fi

        linecount=$((linecount+1))
    done < "${infile}"

    if [ "${founderror}" -eq "0" ] ; then
        output_line "No problems found."
    else
        # Output a line feed for line numbers progress output
        if [ -n "${verbose}" ] ; then
            >&2 echo
        fi
    fi

else
    >&2 echo "ERROR: Unable to read input CSV file or ACCESS Organizations file."
fi

####################
# END MAIN PROGRAM #
####################
