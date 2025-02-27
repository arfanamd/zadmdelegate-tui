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
# due to performance concerns. Instead, we’ll utilize the ldapsearch
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
trap '{ command rf -f "${_dialogOut}" "${_zmprovOut}"; }'

# Initialize dialog
_box_w=$[ $(tput cols) / 2 ]
_box_h=$[ $(tput lines) / 2 ]
[[ -f "${PWD}/zadmdelegate-tui.rc" ]] && { export DIALOGRC="${PWD}/zadmdelegate-tui.rc"; }
export DIALOGTTY=1

# show message using dialog
info() { command dialog --clear --msgbox "${1}" ${_box_h} ${_box_w}; }


# vim:ft=bash:ts=4:sw=4:et
