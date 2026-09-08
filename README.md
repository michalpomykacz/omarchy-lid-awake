# Lid awake

Omarchy bar toggle: while it is on, closing the laptop lid does not suspend.

While it is off the glyph stays hidden and reveals on hovering the adjacent
`omarchy.indicators` cluster, the same way the built-in indicators behave. Drop
the cluster from the bar and it stays permanently visible instead, so the
toggle never becomes unreachable.

Click the laptop glyph, or drive it from a script:

    omarchy-shell lid status     # awake | suspend
    omarchy-shell lid toggle
    omarchy-shell lid on
    omarchy-shell lid off

## How it works

It holds a logind `handle-lid-switch` inhibitor lock
(`systemd-inhibit --what=handle-lid-switch --mode=block`) for as long as the
toggle is on. Taking that lock is permitted for the active session, so nothing
here needs root, a polkit prompt, or an edit to `/etc/systemd/logind.conf`.

The setting is stored in `~/.local/state/omarchy/indicators/lid-awake` and
survives a shell restart or a relog. It does *not* survive a reboot as an
active inhibitor — the file is read back at shell start and the lock retaken.

Lid close still locks the screen and reconfigures displays: that is Omarchy's
own `switch:on:Lid Switch` binding, which this plugin deliberately leaves
alone.

## Install

    omarchy plugin add https://github.com/michalpomykacz/omarchy-lid-awake.git --enable --yes
    omarchy bar move io.github.michalpomykacz.lid-awake --section center

## Removal

    omarchy plugin remove io.github.michalpomykacz.lid-awake --yes

That drops the plugin directory and its bar entry. Any inhibitor lock dies with
the shell process that held it, so lid handling returns to the logind default
immediately — nothing is left behind in `/etc`, because nothing was ever put
there. The one leftover is the saved toggle state, if you want it gone too:

    rm -f ~/.local/state/omarchy/indicators/lid-awake

## Development

The installer clones into `~/.config/omarchy/plugins/<manifest id>/`, which is
a second copy of the repo — fine for using the plugin, awkward for changing it.
Symlink a working checkout in its place instead, so there is one source of
truth:

    git clone https://github.com/michalpomykacz/omarchy-lid-awake.git
    ln -s "$PWD/omarchy-lid-awake" \
      ~/.config/omarchy/plugins/io.github.michalpomykacz.lid-awake
    omarchy-shell shell rescanPlugins
    omarchy plugin enable io.github.michalpomykacz.lid-awake

The plugin scanner globs directories and follows symlinks, so this is
discovered normally. Note that editing QML through a symlink does not reliably
trip the shell's hot reload, and `rescanPlugins` alone re-reads manifests
without re-instantiating live widgets — `omarchy restart shell` is the
dependable way to see a change.

## Requirements

Omarchy Quattro (`omarchy-shell`) and systemd-logind.

## Check

    ./test.sh

Cycles the toggle and asserts the reported state, the persisted state, and the
held inhibitor locks agree — including that "off" really drops every lock.

## License

MIT — see [LICENSE](LICENSE).
