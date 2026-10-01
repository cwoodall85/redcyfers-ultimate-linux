# /etc/profile.d/ultimate-path.sh -- from ultimate-boot.
# BLFS's /etc/profile puts /usr/sbin on the PATH for root only, so a user
# can't find ip, efibootmgr, nft, ... Arch and Fedora give it to everyone.
case ":$PATH:" in *:/usr/sbin:*) ;; *) PATH=$PATH:/usr/sbin ;; esac
export PATH
