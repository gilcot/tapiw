#!/bin/sh
# ex: ai:sw=4:ts=4
# vim: ai:ft=sh:sw=4:ts=4:ff=unix:sts=4:et:fenc=utf8
# -*- sh; c-basic-offset: 4; indent-tabs-mode: nil; tab-width: 4; 
# atom: set UseSoftTabs tabLength=4 encoding=utf-8 lineEnding=lf grammar=shell:
# mode: shell; tabsoft; tab:4; encoding: utf-8; coding: utf-8;
###########################################################################
# Command Line Interface to TeamPass API (see README)

# those are needed by the script
for _i in awk base64 curl grep jq tty
do
    if ! command -v $_i >/dev/null
    then
        echo "$_i not in $PATH" >&2
        exit 1
    fi
done

# load paramaters
if test -r /etc/tp_cli.rc
then
    . /etc/tp_cli.rc
fi
if test -r $HOME/.tp_cli.rc
then
    . $HOME/.tp_cli.rc
fi
tp_a='read'
tp_c='items'
tp_u="${TEAMPASS_URL:-https://$(hostname)}"
tp_k="$TEAMPASS_APIKEY"
tp_o="$CURL_OPTIONS"

# overidde parameters
while getopts "BHa:c:g:hi:k:m:o:r:s:u:v" arg
do
    case $arg in
        v)
            echo "tpcli.sh-0.9.1"
            exit 0
            ;;
        h)
            echo "syntax: $0 [parameter value]... [switch]... Ids..."
            echo "those parameters may be defined as variable in {/etc,~}/tp_cli.rc"
            echo " -u: TEAMPASS_URL"
            echo " -k: TEAMPASS_APIKEY"
            echo " -o: CURL_OPTIONS"
            echo "those parameters can only be specified in invocation command line"
            echo " -a: action (read --default-- or write)"
            echo " -c: component (items --default, folder, etc.)"
            echo " -r: restrict search to those folders"
            echo "switches are used to change default behaviour so"
            echo " -B: batch mode, i.e. no interactive prompt"
            echo " -H: don't show headers first"
            exit 0
            ;;
        B) # batch
            tp_B=1
            ;;
        H) # headers
            tp_H=1
            ;;
        a|m) # action|method
            tp_a="$( echo "$OPTARG" | awk '{print tolower($0)}' )"
            ;;
        c) # component
            tp_c="$( echo "$OPTARG" | awk '{print tolower($0)}' )"
            ;;
        i) # id(s)
            tp_i="$OPTARG"
            ;;
        k) # key
            tp_k="$OPTARG"
            ;;
        o) # options for curl
            tp_o="$OPTARG"
            ;;
        r) # restrict
            tp_r="$OPTARG"
            ;;
        s|u) # url|site
            tp_u="$OPTARG"
            ;;
        *)
            #echo "syntax: $0 [-u|-s <site_url>] [-k <apikey>] [-l <user_login>] [-p <user_password>] [-c <component>] [-B] [-H] [-o <curl_options>] <ids> " >&2
            exit 1
            ;;
    esac
    shift $(( OPTIND - 1 ))
    #echo "DEBUG: $OPTIND less, remain $*"
done

# auto-switch to batch if no term
tty -s || tp_B=1

# Function to fail with message
# $1 = optional error message
# $2 = optional exit code
_fail() {
    echo "${1:-Abort}" >&2
    exit $(( $2 ))
}

# note: as ${!foo} isn't POSIX, we use _temp
_temp=''
# Function to prompt some entry
# $1 = requiered input variable
# $2 = requiered prompt message
# $3 = optional  default value
# $4 = optional  failure message
# $5 = optional  if set disable failure on no value
_prompt() {
    test $# -lt 2 && return
    test -z "$_temp" && _temp="$3"
    if test -z "$tp_B" && test -z "$_temp"
    then
        printf "%b?\t" "$2"
        read -r _temp
        if test -z "$5"
        then
            test -z "$_temp" && _fail "$4" 2
        fi
    fi
    eval "$1='$_temp'"
    _temp=''
}

# API endpoint
if echo "$tp_u" | grep -qsv '/$'
then
    tp_u="$tp_u/"
fi
if echo "$tp_u" | grep -qs '/index\.php'
then
    tp_u="$( echo "$tp_u" |
        awk '{gsub("/index\.php.*$","/",$0); print $0}' 2>/dev/null )"
fi
if echo "$tp_u" | grep -qsv '/api/$'
then
    tp_u="${tp_u}api/"
fi
tp_u="${tp_u}index.php"

# test instance address
# output should be: {"err":"Something happen ... but what ?"}
curl $tp_o -o /dev/null -sS "$tp_u" ||
    _fail "Network error or bad API EndPoint: $tp_u/" 1

# API access key
_prompt 'tp_k' "API key" "$tp_k" \
    "No option -k and no TEAMPASS_APIKEY in config file, but that's required..."
tp_k="?apikey=$tp_k"

# Function to concatene Multiple Ids List into one argument
# $* = requiered space separated items
_mil() {
    echo "$*" |
        awk '{out=$1; for(i=2;i<=NF;i++){out=out";"$i}; print out}'
}

# Function to Encode Data String part according to
# $1 = requiered string to enconde
#@ https://teampass.readthedocs.io/en/latest/api/api-write/#information-about-base64_encoding
# note that spaces are trimed, in order to allow the use of _prompt for empty fields
_eds() {
    printf '%s' "$( echo "$1" |
        awk '{gsub(/^[ \t]+/,"",$0); gsub(/[ \t]+$/,"",$0); print $0}' )" |
        base64 -w 0 |
        awk '{gsub("\+","-",$0); gsub("/","_",$0); print $0}'
}

# Function to make a simple GET query against the TP API EP
# $1 = requiered the request as method/component/parameter but key
_get() {
    test $# -lt 1 && return
    #echo "DEBUG: curl $tp_u/$tp_a/$1$tp_k"
    _json=$( curl -s $tp_o -H 'Content-Type: application/json; charset=utf8' "$tp_u/$tp_a/$1$tp_k" | grep -s '^{' )
    #echo "DEBUG: $_json"
    if jq --version | awk -F '-' '{print $2}' | grep -qs '1\.[1-4]' # jq-X.Y-Z-misc
    then
        # 1.5 knows keys_unsorted and @tsv, 1.4 doesn't
        _out='@csv'
    else
        _out='@tsv'
    fi
    if echo "$_json" | grep -qs '} *}$'
    then
        # output type 1: {"_id1":{...},"_id2":{...},...,"_idN":{...}}
        if test -z "$tp_H"
        then
            echo "$_json" |
                jq -r "[ .[] ] | .[0] | keys | $_out"
        fi
        echo "$_json" |
            jq -r "(.[] | [ .[] ]) | [ .[] ] | $_out"
    elif echo "$_json" | grep -qs '^{"err":'
    then
        # output type 2 ; special/error case
        test -z "$tp_H" && echo "ErRoR"
        echo "$_json" | jq -r '.err'
    else
        # output type 2 : {"key1":"value1",...,"keyN":"valueN"}
        # e.g. for: status, password, etc.
        if test -z "$tp_H"
        then
            echo "$_json" |
                jq -r "keys | $_out"
        fi
        echo "$_json" |
            jq -r "[ .[] ] | @tsv"
    fi
}

# labels/question shown
l_tf=" boolean integer:\n 0 false\n 1 true\n"
l_g0="Folder Id"
l_g1=" folder title (public)\n user login (personal)\nFolder Name"
l_g2=" integer in:\n 00 very weak,\n 25 weak,\n 50 mean,\n 60 strong,\n 70 very strong,\n 80 sure,\n 90 very sure\nComplexity Lvl"
l_g3=" boolean integer:\n 0 public\n 1 personal\nFolder Type"
l_g4=" days integer, 0 for unlimited\nRenewal Period"
l_g5=" 0 for root level\nParent Id"
l_g8="Folder Title"
l_g9="Folder(s) Id(s)"
l_i0="Item Id"
l_i1="Unique Label"
l_i2="Password"
l_i3="Description"
l_i5="Login"
l_i6="E-mail"
l_i7="Web Address"
l_i8=" space delimited words\nTags List"
l_i4="${l_tf}Any one can modify"
l_i9="Item(s) Id(s)"
l_u0="User Login"

# dispatch per actions then components
case $tp_a in
    new_password|new/password|generate_password|generate/password)
    #@ https://teampass.readthedocs.io/en/latest/api/api-special/#generate-a-password
        tp_a='new_password'
        _prompt 'tp_1' " integer taken from 4 to 50\nSize/Length" "$1"
        _prompt 'tp_2' "${l_tf}is Secure" "$2"
        _prompt 'tp_3' "${l_tf}has Numerals" "$3"
        _prompt 'tp_4' "${l_tf}has Capitals" "$4"
        _prompt 'tp_5' "${l_tf}has Ambiguous" "$5"
        _prompt 'tp_6' "${l_tf}has Symbols" "$6"
        _prompt 'tp_7' "${l_tf} mandatory with symbols\nBase64 Enc." "$7"
        _get "$(( tp_1 ));$(( tp_2 ));$(( tp_3 ));$(( tp_4 % 2 ));$(( tp_5 % 2 ));$(( tp_6 % 2 ));$(( tp_6?1:tp_7 % 2 ))"
        ;;
    auth)
    #@ https://teampass.readthedocs.io/en/latest/api/api-special/#authentication-credentials-for-a-web-page
        _prompt 'tp_1' " (i.e. http|https|ftp|ftps|etc.)\nProtocol" "$1"
        _prompt 'tp_2' " (i.e. without the protocol and /)\nBase URL" "$2" '' 'AllowEmpty'
        _prompt 'tp_3' "Your Login" "${TEAMPASS_LOGIN:-$3}"
        _prompt 'tp_4' "Pass Word" "${TEAMPASS_PASSWORD:-$4}"
        _get "$tp_1/$tp_2/$tp_3/$tp_4"
        ;;
    find|search_in_folder|search_in_folders|look_in_folder|look_in_folders)
    #@ https://teampass.readthedocs.io/en/latest/api/api-read/#find-items
        tp_a='find'
        _prompt 'tp_r' "$l_g9" "${tp_r:-$1}"
        _prompt 'tp_i' "Search Pattern" "${tp_i:-$2}"
        _get "item/$( _mil "$tp_r" )/$tp_i"
        ;;
    cat|dir|display|get|list|ls|more|read|retrieve|see|select|show|view)
    #@ https://teampass.readthedocs.io/en/latest/api/api-read/#overview
        tp_a='read'
        case $tp_c in
            folder|folders|group|groups)
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#read-folders
                _prompt 'tp_i' "$l_g9" "${tp_i:-$@}"
                # https://github.com/nilsteampassnet/TeamPass/issues/2307
                _get "folder/$( _mil "$tp_i" )"
            ;;
            entry|entries|item|items|pw)
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#read-specific-items
                _prompt 'tp_i' "$l_i9" "${tp_i:-$@}"
                _get "items/$( _mil $tp_i )"
            ;;
            userpw|useritems|userfolders)
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#read-users-items
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#read-users-folders
                test "$tp_c" = 'useritems' && tp_c='userpw'
                _prompt 'tp_i' "$l_u0" "${tp_i:-$1}"
                _get "$tp_c/$( echo "$tp_i" | awk '{print $1}' )"
            ;;
            listattachments|listfiles)
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#list-itemss-file-attachments
                _prompt 'tp_i' "$l_i0" "${tp_i:-$1}"
                _get "listfiles/$( echo "$tp_i" | awk '{print $1}' )"
            ;;
            files|file|attachment|getfile|getattachment|retrievefile|retrieveattachment)
            #@ https://teampass.readthedocs.io/en/latest/api/api-read/#download-itemss-file-attachments
                tp_c='files'
                _prompt 'tp_i' "File Id" "${tp_i:$1}"
                curl -s $tp_o "$tp_u/$tp_a/$tp_c/$( echo "$tp_i" | awk '{print $1}' )$tp_k" -o "teampass_attachment_$tp_i"
            ;;
            folder_descendants|folders_descendants|folders_recursive|subfolders)
            #@ https://teampass.userecho.com/communities/1/topics/106-search-item-by-label-via-api-without-folderid
            #@ https://teampass.userecho.com/communities/1/topics/85-api-list-folder-by-label-or-list-all-folders
                _prompt 'tp_r' "$l_g0" "${tp_r:-$1}"
                tp_r="$( echo "$tp_r" | awk '{print tolower($1)}' )"
                if "tp_r" = 'title'
                then
                    _prompt 'tp_i' "$l_g8" "${tp_i:-$2}"
                elif "tp_r" = 'id'
                then
                    _prompt 'tp_i' "$l_g0" "${tp_i:-$2}"
                else
                    _fail "Bad Answer..."
                fi
                _get "$tp_c/$tp_r/$( echo "$tp_i" | awk '{print $1}' )"
            ;;
            category)
            #@ https://github.com/jle64/teampassclient
                _prompt 'tp_r' "Category Id" "${tp_r:-$1}"
                _prompt 'tp_i' "Search Label" "${tp_i:-$2}"
                _get "$tp_c/$( echo "$tp_r" | awk '{print $1}' )/$tp_i"
            ;;
            *)
                _get "$tp_c/$( _mil "${tp_i:-$@}"  )"
            ;;
        esac
        ;;
    about|info|stat|what)
    #@ https://teampass.readthedocs.io/en/latest/api/api-special
        tp_a='info'
        # https://github.com/nilsteampassnet/TeamPass/issues/1665
        case $tp_c in
            folder|group)
                _prompt 'tp_1' "$l_g1" "$1"
                _get "$tp_c/$( _mil "${tp_i:-$@}"  )"
            ;;
            complexitity_levels_list|version|*)
                _get "$tp_c"
            ;;
        esac
        ;;
    delete|erase|drop|purge|remove|rm|suppress|trash|undo|unlink)
    #@ https://teampass.readthedocs.io/en/latest/api/api-write
        tp_a='delete'
        case $tp_c in
            folder|folders|group|groups)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#delete-a-folder
                _prompt 'tp_i' "$l_g9" "${tp_i:-$@}"
                # https://github.com/nilsteampassnet/TeamPass/issues/2307
                _get "folder/$( _mil "$tp_i" )"
            ;;
            entry|entries|item|items|pw)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#delete-an-item
                _prompt 'tp_i' "$l_i9" "${tp_i:-$@}"
                _get "item/$( _mil $tp_i )"
            ;;
            *)
                _get "$tp_c/$( _mil "${tp_i:-$@}"  )"
            ;;
        esac
        ;;
    add|create|insert|link|make|mk|mkdir|new|put|post|touch|write)
    #@ https://teampass.readthedocs.io/en/latest/api/api-write
        tp_a='add'
        case $tp_c in
            folder|group)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_1' "$l_g1" "$1"
                _prompt 'tp_2' "$l_g2" "$2"
                _prompt 'tp_5' "$l_g5" "$5"
                _prompt 'tp_3' "$l_g3" "$3"
                _prompt 'tp_4' "$l_g4" "$4"
                #_get "folder/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds $(( tp_3 % 2 )) )"
                _get "folder/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));$(( tp_3 % 2 ))" )"
            ;;
            publicfolder)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_1' "$l_g8" "$1"
                _prompt 'tp_2' "$l_g2" "$2"
                _prompt 'tp_5' "$l_g5" "$4"
                _prompt 'tp_4' "$l_g4" "$3"
                #_get "folder/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds 0 )"
                _get "folder/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));0" )"
            ;;
            userfolder)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_1' "$l_u0" "$1"
                _prompt 'tp_2' "$l_g2" "$2"
                _prompt 'tp_5' "$l_g5" "$4"
                _prompt 'tp_4' "$l_g4" "$3"
                #_get "folder/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds 1 )"
                _get "folder/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));1" )"
            ;;
            entry|item|pw)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-an-item
                _prompt 'tp_1' "$l_i1" "$1"
                _prompt 'tp_2' "$l_i2" "$2"
                _prompt 'tp_3' "$l_i3" "$3" '' 'AllowEmpty'
                _prompt 'tp_4' "$l_g0" "$4" #
                _prompt 'tp_5' "$l_i5" "$5" '' 'AllowEmpty'
                _prompt 'tp_6' "$l_i6" "$6" '' 'AllowEmpty'
                _prompt 'tp_7' "$l_i7" "$7" '' 'AllowEmpty'
                _prompt 'tp_8' "$l_i8" "$8" '' 'AllowEmpty'
                _prompt 'tp_9' "$l_i4" "$9" #
                _get "item/$( _eds "$tp_1" );$( _eds "$tp_2" );$( _eds "$tp_3" );$( _eds $(( tp_4 )) );$( _eds "$tp_5" );$( _eds "$tp_6" );$( _eds "$tp_7" );$( _eds "$tp_8" );$( _eds $(( tp_9 % 2)) )"
            ;;
            user)
            #@ https://teampass.readthedocs.io/en/latest/api/api-special/#add-new-user
                _prompt 'tp_1' "$l_u0" "$1"
                _prompt 'tp_2' "User First Name" "$2"
                _prompt 'tp_3' "User Last Name" "$3"
                _prompt 'tp_4' "User Password" "$4"
                _prompt 'tp_5' "${l_tf}is AdministratedBy" "$5" '' 'AllowEmpty'
                _prompt 'tp_6' "${l_tf}is Read Only" "$6" '' 'AllowEmpty'
                _prompt 'tp_7' "${l_tf}is Administrator" "$7" '' 'AllowEmpty'
                _prompt 'tp_8' "${l_tf}is Users Manager" "$8" '' 'AllowEmpty'
                _prompt 'tp_9' "${l_tf}has Own Folder" "$9" '' 'AllowEmpty'
                #_get "user/$( _eds "$tp_1" );$( _eds "$tp_2" );$( _eds "$tp_3" );$( _eds "$tp_4" );$( _eds $(( tp_5 % 2 )) );$( _eds $(( tp_6 % 2 )) );$( _eds $(( tp_7 % 2 )) );$( _eds $(( tp_8 % 2 )) );$( _eds $(( tp_9 % 2 )) )"
                _get "user/$( _eds "$tp_1;$tp_2;$tp_3;$tp_4;$(( tp_5 % 2 ));$(( tp_6 % 2 ));$(( tp_7 % 2 ));$(( tp_8 % 2 ));$(( tp_9 % 2 ))" )"
            ;;
            attachment|file)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-new-file-attachment
                _prompt 'tp_i' "$l_i0" "${tp_i:-$2}"
                _prompt 'tp_r' "File Path" "${tp_r:-$1}"
                curl -X POST -s $tp_o "$tp_u/$tp_a/file$tp_k" \
                    -F "item_id=$(( tp_i ))" \
                    -F "file=@$tp_r;filename=$( basename "$tp_i" )"
            ;;
            *)
                _fail "Unmanaged component for $tp_a: $tp_c" 2
            ;;
        esac
        ;;
    alter|change|correct|edit|modify|redo|patch|replace|update)
    #@ https://teampass.readthedocs.io/en/latest/api/api-write
        tp_a='update'
        case $tp_c in
            entry|item|pw)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#update-an-item
                _prompt 'tp_0' "$l_i0" "$1"
                _prompt 'tp_1' "$l_i1" "$2"
                _prompt 'tp_2' "$l_i2" "$3"
                _prompt 'tp_3' "$l_i3" "$4"
                _prompt 'tp_4' "$l_g0" "$5" #
                _prompt 'tp_5' "$l_i5" "$6" '' 'AllowEmpty'
                _prompt 'tp_6' "$l_i6" "$7" '' 'AllowEmpty'
                _prompt 'tp_7' "$l_i7" "$8" '' 'AllowEmpty'
                _prompt 'tp_8' "$l_i8" "$9" '' 'AllowEmpty'
                _prompt 'tp_9' "$l_i4" "${10}" #
                _get "item/$tp_0/$( _eds "$tp_1" );$( _eds "$tp_2" );$( _eds "$tp_3" );$( _eds $(( tp_4 )) );$( _eds "$tp_5" );$( _eds "$tp_6" );$( _eds "$tp_7" );$( _eds "$tp_8" );$( _eds $(( tp_9 % 2)) )"
            ;;
            folder|group)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_0' "$l_g0" "$1"
                _prompt 'tp_1' "$l_g1" "$2"
                _prompt 'tp_2' "$l_g2" "$3"
                _prompt 'tp_5' "$l_g5" "$6"
                _prompt 'tp_3' "$l_g3" "$4"
                _prompt 'tp_4' "$l_g4" "$5"
                #_get "folder/$(( tp_0 ))/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds $(( tp_3 % 2 )) )"
                _get "folder/$(( tp_0 ))/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));$(( tp_3 % 2 ))" )"
            ;;
            publicfolder)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_0' "$l_g0" "$1"
                _prompt 'tp_1' "$l_g8" "$2"
                _prompt 'tp_2' "$l_g2" "$3"
                _prompt 'tp_5' "$l_g5" "$5"
                _prompt 'tp_4' "$l_g4" "$4"
                #_get "folder/$(( tp_0 ))/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds 0 )"
                _get "folder/$(( tp_0 ))/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));0" )"
            ;;
            userfolder)
            #@ https://teampass.readthedocs.io/en/latest/api/api-write/#add-a-folder
                _prompt 'tp_0' "$l_g0" "$1"
                _prompt 'tp_1' "$l_u0" "$2"
                _prompt 'tp_2' "$l_g2" "$3"
                _prompt 'tp_5' "$l_g5" "$5"
                _prompt 'tp_4' "$l_g4" "$4"
                #_get "folder/$(( tp_0 ))/$( _eds "$tp_1" );$( _eds $(( tp_2 )) );$( _eds $(( tp_5 )) );$( _eds $(( tp_4 )) );$( _eds 1 )"
                _get "folder/$(( tp_0 ))/$( _eds "$tp_1;$(( tp_2 ));$(( tp_5 ));$(( tp_4 ));1" )"
            ;;
            *)
                _fail "Unmanaged component for $tp_a: $tp_c" 2
            ;;
        esac
        ;;
    *)
    #@
        _fail "Action/Method not handled yet: $tp_a" 2
        ;;
esac
