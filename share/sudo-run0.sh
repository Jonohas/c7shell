# c7shell: an interactive `sudo` asks through polkit -- the shell's popup,
# fingerprint and all -- by handing the command to run0. Sourced from
# ~/.zshrc and ~/.bashrc by c7shell-setup; works in either shell.
#
# Only in an interactive shell of a local graphical session. Over ssh there is
# no popup to show and no one at this screen to answer it, and scripts never
# see this function, so their `sudo` keeps its exact semantics.
#
# Only for the forms run0 means the same way: `sudo CMD`, `sudo -u USER CMD`
# and a bare `sudo -i` / `sudo -s` for a root shell. Anything else -- -E, -k,
# -v, -l, sudoedit -- is real sudo, prompting on the terminal as it always did.
# `command sudo ...` reaches real sudo on purpose too.
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

if [ -z "${SSH_CONNECTION-}${SSH_TTY-}" ] && [ -n "${WAYLAND_DISPLAY-}" ] \
   && command -v run0 >/dev/null 2>&1; then
  sudo() {
    case $# in 0) command sudo; return ;; esac
    case $1 in
      -i|-s) if [ $# -eq 1 ]; then run0; else command sudo "$@"; fi ;;
      -u) if [ $# -ge 3 ]; then run0 --user="$2" "${@:3}"; else command sudo "$@"; fi ;;
      -*) command sudo "$@" ;;
      *) run0 "$@" ;;
    esac
  }
fi
