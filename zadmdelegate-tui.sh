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

# Revert every initialization modification for this program to run & clean up.
trap '{
    command rm -f "${_dialogOut}" "${_zmprovOut}"
    tput cnorm
    DIALOGRC="${OLD_DIALOGRC}"
}' EXIT

# Global variables
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

# make cursor invicible
command tput civis

# show message using dialog
info() { command dialog --clear --msgbox "${1}" ${_box_h} ${_box_w}; }

selectAdministratorGroup() { # {{{
    local groups=($( \
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=zimbraDistributionList)(zimbraIsAdminGroup=TRUE))' mail \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    command dialog --clear --colors --no-items --menu "\
Select the admin groups to which you want to grant or revoke access for one or more rules. \
Note that, only DL with \Zb\Z3zimbraIsAdminGroup\Zn attribute set to TRUE that gets listed \
in here.\n\nChoose the group:\n\n" ${_box_h} ${_box_w} ${#groups[@]} ${groups[@]} 2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _group < "${_dialogOut}"
} # }}}

selectTargetDomains() { # {{{
    local domains=($(\
        command ldapsearch -H ${_zldap_h} -LLL -x -D ${_zldap_u} -w ${_zldap_p} \
        '(&(objectClass=dcObject))' zimbraDomainName \
        | command sed -e '/^$/d;/^dn:/d;s/^.\+: //' \
    ))

    command dialog --clear --colors --no-items --checklist \
"You can select one or more target domain for \Zb\Z4${_group}\Zn.\n\n\Zb\Z3NOTE: Use \
space button to toggle selection ON or OFF\Zn\n\n" ${_box_h} ${_box_w} ${#domains[@]} \
    $(for ((i = 0; i < ${#domains[@]}; ++i)); do printf "${domains[i]} off "; done) \
    2> "${_dialogOut}"

    _retval=${?}
    command mapfile -d ' ' -t _domains < "${_dialogOut}"
} # }}}

selectRights() { # {{{
    command dialog --clear --colors --no-cancel --extra-button \
        --ok-label "GRANT" --extra-label "REVOKE" --checklist \
"Select any rights for \Zb\Z4${_group}\Zn:\n\n\Zb\Z3NOTE: Use space button to toggle \
selection ON or OFF\Zn\n\n" ${_box_h} ${_box_w} 12 \
        0  'View Domain' 'off' \
        1  'View Class of services' 'off' \
        2  'Manage Domain' 'off' \
        3  'Manage Class of services' 'off' \
        4  'Manage Account, Alias, and Resource' 'off' \
        5  '+-> Can view account' 'off' \
        6  '+-> Can enable/disable feature' 'off' \
        7  'Manage Distribution list' 'off' \
        8  'Global search, Save search, and Download' 'off' \
        9  'Monitor Server status' 'off' \
        A  'Monitor queue and statistics' 'off' \
        B  'Almost like Global Admin' 'off' \
        2> "${_dialogOut}"

        _retval=${?}
        command mapfile -d ' ' -t _rights < "${_dialogOut}"
} # }}}

actionChoosedRights() { # {{{
    local action=${1}
    local grant='revokeRight'
    local opr='-'

    if [[ ${action} -eq 0 ]]; then
        grant='grantRight'
        opr='+'
        printf "mdl ${_group} zimbraIsAdminGroup TRUE zimbraMailStatus disabled zimbraHideInGal TRUE \n" \
        >> "${_zmprovOut}"
    fi

    printf "\
${grant} zimlet com_zimbra_delegatedadmin grp ${_group} +getZimlet
${grant} zimlet com_zimbra_delegatedadmin grp ${_group} +listZimlet
" >> "${_zmprovOut}"

    for domain in "${_domains[@]}"; do
        for right in "${_rights[@]}"; do
            case ${right} in
                0) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents domainListView
${grant} domain ${domain} grp ${_group} +accessGAL
${grant} domain ${domain} grp ${_group} +adminConsoleDomainThemesTabRights
${grant} domain ${domain} grp ${_group} +checkDomainMXRecord
${grant} domain ${domain} grp ${_group} +configureWikiAccount
${grant} domain ${domain} grp ${_group} +countAccount
${grant} domain ${domain} grp ${_group} +countAlias
${grant} domain ${domain} grp ${_group} +countCalendarResource
${grant} domain ${domain} grp ${_group} +countDistributionList
${grant} domain ${domain} grp ${_group} +getDomain
${grant} domain ${domain} grp ${_group} +listAccount
${grant} domain ${domain} grp ${_group} +listAlias
${grant} domain ${domain} grp ${_group} +listCalendarResource
${grant} domain ${domain} grp ${_group} +listDistributionList
${grant} domain ${domain} grp ${_group} +listDomain
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainAuthenticationTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainDocumentsTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainFreebusyTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainGALTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainInfoTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainLimitsTab
${grant} domain ${domain} grp ${_group} +viewAdminConsoleDomainVirtualHostsTab
${grant} domain ${domain} grp ${_group} +getDomainQuotaUsage
${grant} domain ${domain} grp ${_group} +countDomain
" >> "${_zmprovOut}";; # view domain

                1) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents COSListView
${grant} global grp ${_group} +viewAdminConsoleCOSACLTab
${grant} global grp ${_group} +viewAdminConsoleCOSAdvancedTab
${grant} global grp ${_group} +viewAdminConsoleCOSFeaturesTab
${grant} global grp ${_group} +viewAdminConsoleCOSInfoTab
${grant} global grp ${_group} +viewAdminConsoleCOSMobileTab
${grant} global grp ${_group} +viewAdminConsoleCOSPreferencesTab
${grant} global grp ${_group} +viewAdminConsoleCOSServerPoolTab
${grant} global grp ${_group} +viewAdminConsoleCOSThemesTab
${grant} global grp ${_group} +viewAdminConsoleCOSZimletsTab
${grant} global grp ${_group} +viewAdminConsoleResourcesPropertiesTab
${grant} global grp ${_group} +listCos
${grant} global grp ${_group} +getCalendarResourceInfo
${grant} global grp ${_group} +getCos
${grant} global grp ${_group} +listZimlet
${grant} global grp ${_group} +getZimlet
${grant} global grp ${_group} +listServer
${grant} global grp ${_group} +getServer
" >> "${_zmprovOut}";; # view class of services

                2) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents domainListView
${grant} domain ${domain} grp ${_group} +adminConsoleDomainRights
${grant} domain ${domain} grp ${_group} +domainAdminDomainRights
${grant} domain ${domain} grp ${_group} +adminConsoleSubDomainRights
${grant} domain ${domain} grp ${_group} +getDomainQuotaUsage
${grant} global grp ${_group} +countDomain
${grant} global grp ${_group} +adminConsoleCreateTopDomainRights
" >> "${_zmprovOut}";; # manage domain

                3) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents COSListView
${grant} global grp ${_group} +adminConsoleCOSRights
${grant} global grp ${_group} +getCos
${grant} global grp ${_group} +countCos
${grant} global grp ${_group} +createCos
${grant} global grp ${_group} +assignCos
${grant} global grp ${_group} +configureCosConstraint
${grant} global grp ${_group} +manageZimlet
${grant} global grp ${_group} +listZimlet
${grant} global grp ${_group} +getZimlet
${grant} global grp ${_group} +listServer
${grant} global grp ${_group} +getServer
${grant} domain ${domain} grp ${_group} +listAccount
${grant} domain ${domain} grp ${_group} +listDomain
" >> "${_zmprovOut}";; # manage cos

                4) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents accountListView ${opr}zimbraAdminConsoleUIComponents aliasListView ${opr}zimbraAdminConsoleUIComponents resourceListView
${grant} domain ${domain} grp ${_group} +domainAdminAccountRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAccountRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAccountsFreeBusyInteropTabRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAccountsThemesTabRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAccountsAliasesTabRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAliasRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleDLAliasesTabRights
${grant} domain ${domain} grp ${_group} +adminConsoleAliasRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleRights
${grant} domain ${domain} grp ${_group} +adminConsoleAccountRights
${grant} domain ${domain} grp ${_group} +domainAdminCalendarResourceRights
${grant} domain ${domain} grp ${_group} +domainAdminConsoleResourceRights
${grant} domain ${domain} grp ${_group} +adminConsoleResourceRights
${grant} domain ${domain} grp ${_group} +countCalendarResource
${grant} domain ${domain} grp ${_group} +changeCalendarResourcePassword
${grant} domain ${domain} grp ${_group} +modifyCalendarResource
${grant} global grp ${_group} +assignCos
${grant} global grp ${_group} +getCos
${grant} global grp ${_group} +viewAdminConsoleDomainLimitsTab
" >> "${_zmprovOut}";; # manage account

                5) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents accountListView
${grant} zimlet com_zimbra_viewmail grp ${_group} getZimlet
${grant} zimlet com_zimbra_viewmail grp ${_group} listZimlet
${grant} domain ${domain} grp ${_group} +adminLoginAs
" >> "${_zmprovOut}";; # view account

                6) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents accountListView
${grant} domain ${domain} grp ${_group} +domainAdminConsoleAccountsFeaturesTabRights
${grant} domain ${domain} grp ${_group} +adminConsoleAccountsFeaturesTabRights
" >> "${_zmprovOut}";; # enable or disable features

                7) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents DLListView
${grant} domain ${domain} grp ${_group} +domainAdminConsoleDLRights
${grant} domain ${domain} grp ${_group} +domainAdminDistributionListRights
${grant} domain ${domain} grp ${_group} +countDistributionList
${grant} domain ${domain} grp ${_group} +listAccount
" >> "${_zmprovOut}";; # manage DL

                8) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents downloadsView ${opr}zimbraAdminConsoleUIComponents helpSearch ${opr}zimbraAdminConsoleUIComponents saveSearch
${grant} zimlet com_zimbra_bulkprovision grp ${_group} getZimlet
${grant} zimlet com_zimbra_bulkprovision grp ${_group} listZimlet
${grant} domain ${domain} grp ${_group} +listAccount
${grant} domain ${domain} grp ${_group} +listAlias
${grant} domain ${domain} grp ${_group} +listDistributionList
${grant} domain ${domain} grp ${_group} +countAccount
${grant} domain ${domain} grp ${_group} +countAlias
${grant} domain ${domain} grp ${_group} +countDistributionList
${grant} domain ${domain} grp ${_group} +getAccount
${grant} domain ${domain} grp ${_group} +getDistributionList
${grant} domain ${domain} grp ${_group} +domainAdminConsoleSavedSearchRights
${grant} domain ${domain} grp ${_group} +adminConsoleSavedSearchRights
" >> "${_zmprovOut}";; # search & download

                9) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents globalServerStatusView
${grant} global grp ${_group} +adminConsoleServerStatusRights
" >> "${_zmprovOut}";; # server status

                A) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents perServerStatisticsView ${opr}zimbraAdminConsoleUIComponents mailQueue
${grant} global grp ${_group} +adminConsoleServerStatisticRights
${grant} global grp ${_group} +adminConsoleMailQueueRights
" >> "${_zmprovOut}";; # mail queue & server statistic

                B) printf "\
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents accountListView ${opr}zimbraAdminConsoleUIComponents DLListView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents aliasListView ${opr}zimbraAdminConsoleUIComponents resourceListView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents helpSearch ${opr}zimbraAdminConsoleUIComponents saveSearch
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents bulkProvisionTasksView ${opr}zimbraAdminConsoleUIComponents COSListView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents domainListView ${opr}zimbraAdminConsoleUIComponents serverListView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents zimletListView ${opr}zimbraAdminConsoleUIComponents adminZimletListView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents globalConfigView ${opr}zimbraAdminConsoleUIComponents globalServerStatusView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents mailQueue ${opr}zimbraAdminConsoleUIComponents backupsView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents certsView ${opr}zimbraAdminConsoleUIComponents softwareUpdatesView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents perServerStatisticsView ${opr}zimbraAdminConsoleUIComponents globalPermissionView
mdl ${_group} ${opr}zimbraAdminConsoleUIComponents rightListView
${grant} global grp ${_group} +adminConsoleRights
" >> "${_zmprovOut}";; # almost like global admin

            esac
        done
    done

    command printf "Please wait...\n"
    command zmprov -vf "${_zmprovOut}"
} # }}}

# Main {{{
selectAdministratorGroup
[[ ${_retval} -ne 0 ]] && { exerr "Canceling..."; }

selectTargetDomains
[[ ${_retval} -ne 0 ]] && { exerr "Canceling..."; }
[[ ${#_domains[@]} -eq 0 ]] && { info "Please select one or more domain from the list!"; exit; }

selectRights
[[ ${#_rights[@]} -eq 0 ]] && { info "Please select one or more right from the list!"; exit; }
[[ ${_retval} -eq 0 ]] && actionChoosedRights 0
[[ ${_retval} -eq 3 ]] && actionChoosedRights 1

printf "[${_retval}|FINISHED] ${_group} ${_domains[@]} ${_rights[@]}\n"
# }}}

# vim:ft=bash:ts=4:sw=4:et
