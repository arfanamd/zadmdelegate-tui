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

# Log file
_programLog=$(mktemp "${TMPDIR:-/tmp}/programLog.XXXXXX")
[[ ! -f "${_programLog}" ]] && { exerr "Can't create programLog file"; }

# 
_retval=0
_rights=""
_group=""
_domains=""

# Initialize dialog
_box_w=$(tput cols)
_box_h=$(tput lines)

# TODO: check minimum screen size

[[ -f "${PWD}/zadmdelegate-tui.rc" ]] && {
    OLD_DIALOGRC="${DIALOGRC}"
    export DIALOGRC="${PWD}/zadmdelegate-tui.rc"
}
export DIALOGTTY=1

# show message using dialog
info() { command dialog --clear --msgbox "${1}" ${_box_h} ${_box_w}; }

selectAdministratorGroup() { # {{{
    local groups=($( \
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=zimbraDistributionList)(zimbraIsAdminGroup=TRUE))' mail \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    command dialog --clear --no-items --menu "\
Select the admin groups to which you want to grant or revoke access for one or more rules. \
Only DL with zimbraIsAdminGroup attribute set to TRUE that gets listed in here. \
\n\n Choose the groups:" ${_box_h} ${_box_w} ${#groups[@]} ${groups[@]} 2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _group < "${_dialogOut}"
} # }}}

selectTargetDomains() { # {{{
    local domains=($(\
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=dcObject))' zimbraDomainName \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    command dialog --clear --no-items --checklist \
    "You can select one or more target domain for ${_group}" ${_box_h} ${_box_w} ${#domains[@]} \
    $(for ((i = 0; i < ${#domains[@]}; ++i)); do printf "${domains[i]} off "; done) \
    2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _domains < "${_dialogOut}"
} # }}}

selectRights() { # {{{
    local type_of_rights=(
        'View_Domain'
        'View_Class_of_services'
        'Manage_Domain'
        'Manage_Account,_Aliases,_and_Resources'
        '>__Can_view_account'
        '>__Can_enable_or_disable_accounts_feature'
        '>__Can_modify_accounts_quota#'
        'Manage_Distribution_List'
        'Global_Search_and_Download'
    )

    command dialog --clear --no-cancel --extra-button \
        --ok-label "GRANT" --extra-label "REVOKE" --checklist \
        "Select any rights for ${_group}:" ${_box_h} ${_box_w} ${#type_of_rights[@]} \
        $(for ((i = 0; i < ${#type_of_rights[@]}; ++i)); do printf "${i} ${type_of_rights[i]} off "; done) \
        2> "${_dialogOut}"

        _retval=${?}
        command mapfile -d ' ' -t _rights < "${_dialogOut}"
} # }}}

# vim:ft=bash:ts=4:sw=4:et
