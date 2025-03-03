# "THE BEER-WARE LICENSE" (Revision 42):
# 
# As long as you retain this notice you can do whatever you want
# with this stuff. If we meet some day, and you think this stuff
# is worth it, you can buy us a beer in return.
# 
# This project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# 
#!/usr/bin/env bash

exerr() { command printf "[ERROR] %s\n" "${@}"; exit 1; }
chkprg() { command type -p "${1}"; }

# check all requirements
[[ ! $(chkprg sed) ]] && { exerr "You don't have sed installed"; }
[[ ! $(chkprg mktemp) ]] && { exerr "You don't have mktemp installed"; }
[[ ! $(chkprg ldapsearch) ]] && { exerr "You don't have ldapsearch installed"; }
[[ ! $(chkprg dialog) ]] && { exerr "You don't have dialog installed"; }
[[ ! $(chkprg tput) ]] && { exerr "You don't have tput installed"; }
[[ "${USER}" != "zimbra" ]] && { exerr "Please run as zimbra!"; }

command printf "Please wait...\n"

# When querying data, we aim to minimize the use of any zimbra command
# due to performance concerns. Instead, we will utilize the ldapsearch
# command to retrieve the necessary data.
_zldapprop=($(command zmlocalconfig -m nokey -s ldap_master_url zimbra_ldap_userdn zimbra_ldap_password))

_zldap_h="${_zldapprop[0]}"
_zldap_u="${_zldapprop[1]}"
_zldap_p="${_zldapprop[2]}"

unset _zldapprop

# We need temporary files to store the user's input interaction with the
# dialog command.
_dialogOut=$(mktemp "${TMPDIR:-/tmp}/dialogOut.XXXXXX")
[[ ! -f "${_dialogOut}" ]] && { exerr "Can't create dialogOut temporary file"; }

_zmprovOut=$(mktemp "${TMPDIR:-/tmp}/zmprovOut.XXXXXX")
[[ ! -f "${_zmprovOut}" ]] && { exerr "Can't create zmprovOut temporary file"; }

# Remove temporary file on exit
trap '{ command rm -f "${_dialogOut}" "${_zmprovOut}"; }' EXIT

# 
_retval=0
_valret=""

# Initialize dialog
_box_w=$[ $(tput cols) / 2 ]
_box_h=$[ $(tput lines) / 2 ]
[[ -f "${PWD}/zadmdelegate-tui.rc" ]] && { export DIALOGRC="${PWD}/zadmdelegate-tui.rc"; }
export DIALOGTTY=1

# show message using dialog
info() { command dialog --clear --msgbox "${1}" ${_box_h} ${_box_w}; }

selectGroups() {  # {{{
    local groups=($( \
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=zimbraDistributionList)(zimbraIsAdminGroup=TRUE))' mail \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    # TODO: Make users can only select one group at a time.
    # ; Use "menu" instead of "checklist" option for dialog box. 
    command dialog --clear \
        --no-items --checklist \
"Select the admin groups to which you want to grant or revoke access\n
for one or more rules. Only DL with zimbraIsAdminGroup attribute set\n
to TRUE that gets listed in here.\n\n Choose the groups:" ${_box_h} ${_box_w} 0 \
    $(for ((i = 0; i < ${#groups[@]}; ++i)); do printf "${groups[i]} off "; done) \
    2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _valret < "${_dialogOut}"
}  # }}}

selectDomains() {  # {{{
    local group="${1}"
    local domains=($(\
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=dcObject))' zimbraDomainName \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    command dialog --clear \
        --no-items --checklist \
"select one or more target domain for group ${group}" ${_box_h} ${_box_w} 0 \
        $(for ((i = 0; i < ${#domains[@]}; ++i)); do printf "${domains[i]} off "; done) \
        2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _valret < "${_dialogOut}"
}  # }}}

selectRights() {  # {{{
    local group="${1}"
    command dialog --clear --no-cancel \
        --ok-label "GRANT" --extra-button --extra-label "REVOKE" \
        --checklist "select one or more rights for group ${group}" ${_box_h} ${_box_w} 0 \
        "0"  "View domain" "off" \
        "1"  "View class of services" "off" \
        "2"  "View accounts, aliases, and resources" "off" \
        "3"  "Manage domain" "off" \
        "4"  "Manage class of services" "off" \
        "5"  "Manage accounts, aliases, and resources" "off" \
        "6"  "Can enable or disable account's features" "off" \
        "7"  "Can enable or disable account's zimlets" "off" \
        "8"  "Can view account" "off" \
        "9"  "Can change account's quota" "off" \
        "10" "Global search and download (export)" "off" \
        2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _valret < "${_dialogOut}"
}  # }}}
# vim:ft=bash:ts=4:sw=4:et
