#!/bin/sh

# Leave this backslash, so it will be expanded remotely.
LOCK="\$HOME/.${0##*/}.lock"

set -e

usage() {
        cat >&2 << EOF
Usage:
- Fetch + merge:
    Usage:   ${0##*/} sync srchost::srcdir dstdir
    Example: ${0##*/} sync remote.host.net::Mail Mail
    Output:  Whether it appends or creates a mailbox locally.

- Fetch only:
    Usage:   ${0##*/} fetch srchost::srcdir dstdir
    Example: ${0##*/} fetch remote.host.net::Mail Mail
    Output:  Name of the temporary directory in \`dstdir'.

- Merge only:
    Usage:   ${0##*/} merge dstdir/tempdir dstdir
    Example: ${0##*/} merge Mail/sync_mboxes.sh.20140107_13702 Mail
    Output:  Whether it appends or creates a mailbox locally.
EOF
        exit $1
}

lock() {
        if ! eval mkdir $LOCK 2>&1 > /dev/null; then
                echo "ERROR: Local lock dir exists; aborting." >&2
                exit 1
        fi
}

unlock() {
        eval rmdir $LOCK
}

fetch() {
        local script remote_script list tempdir archive pwd=$PWD
        local srchost=$1 srcdir=$2 dst=$3

        #
        # Generate remote script.
        script=`mktemp -t ${0##*/}`
        trap 'rm -f $script' INT TERM EXIT
        remote_script=`ssh $srchost mktemp -t ${0##*/}`

        cat << EOF > $script
if ! mkdir $LOCK 2>&1 >/dev/null; then
        echo "ERROR: Remote lock dir exists; aborting." >&2
        exit 1
fi
cd $srcdir
list=
for f in *; do
        case \$f in
        *.sync) continue ;;
        *.gz|*.bz2|*.xz|*.lzma)
                echo "Compressed mailboxes are not supported," \\
                   "skipping \$f." >&2
                continue
                ;;
        esac
        if [ -f \$f.sync ]; then
                echo "Using previous \$f.sync (\$f NOT synced)." >&2
                list="\$list \$f.sync"
                continue
        fi
        touch empty
        ln \$f \$f.sync >&2
        mv empty \$f >&2
        # Remove empty mailboxes.
        [ -s \$f.sync ] && list="\$list \$f.sync" || rm \$f.sync >&2
done

tar cf - \$list | gzip
rm \$list
rmdir $LOCK
rm $remote_script
EOF

        scp -q $script $srchost:$remote_script

        cd $dst
        tempdir=${0##*/}.`date +%Y%m%d_%H%M%S`

        #
        # Transfer mailboxes to temporary location.
        mkdir $tempdir
        cd $tempdir
        archive=${0##*/}.tar.gz
        ssh $srchost "sh $remote_script" > $archive
        cat $archive | gzip -d | tar xf -
        rm $archive
        for f in *.sync; do
                mv $f ${f%.sync}
        done
        cd $pwd
        echo $tempdir
}

merge() {
        local tempdir=$1 dst=$2 pwd=$PWD

        if [ -z "$tempdir" ]; then
                echo "Missing argument" >&2
                exit 1
        fi

        #
        # Append to local mailboxes.
        if ! [ -d $tempdir ]; then
                echo "No such directory: $tempdir" >&2
                exit 1
        fi
        cd $tempdir
        for mb in `ls`; do
                [ -f ../$mb ] && echo "Appending to $mb" || echo "Creating $mb"
                cat $mb >> ../$mb
                rm $mb
        done
        cd $pwd
        rmdir $tempdir
}

command=$1
shift || true
src=$1
srchost=${1%%::*}
srcdir=${1##*::}
dst=$2

case "$command" in
unlock)
        eval rmdir $LOCK || true
        ssh $src "rmdir $LOCK" || true
        exit 0
        ;;
fetch)
        lock
        fetch $srchost $srcdir $dst
        unlock
        exit 0
        ;;
merge)
        lock
        merge $src $dst
        unlock
        exit 0
        ;;
sync)
        lock
        tempdir=`fetch $srchost $srcdir $dst`
        merge $srcdir/$tempdir $dst
        unlock
        exit 0
        ;;
'')
        usage 0
        ;;
*)
        echo "ERROR: Unknown command" >&2
        usage 1
        ;;
esac
