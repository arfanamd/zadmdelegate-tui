# zadmdelegate-tui

![ss-1](./screenshots/ss-1.gif)

Easily manage what your Zimbra delegated admins can do by giving them only the permissions they need.

## Requirements

* Bash v4.5+
* dialog
* mktemp
* sed
* tput
* ldapsearch

## How to use

* Clone this repo inside any directory that zimbra user have access to it.

```
git clone --depth=1 https://github.com/arfanamd/zadmdelegate-tui
```

* Set the right permission for the script.

```
chmod 755 /path/to/directory/zadmdelegate-tui/zadmdelegate-tui.*
```

* Run the script.

```
/path/to/directory/zadmdelegate-tui/zadmdelegate-tui.sh
```
