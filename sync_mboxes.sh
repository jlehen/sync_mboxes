#!/bin/sh

# Leave this backslash, so it will be expanded remotely.
LOCK="\$HOME/.${0##*/}.lock"

set -e

lock() {
        if ! eval mkdir $LOCK 2>&1 > /dev/null; then
                echo "Local lock dir exists; aborting." >&2
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
        echo "Remote lock dir exists; aborting." >&2
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
        #cat $script
        #eval rmdir $LOCK
        #exit

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
        rm -rf $tempdir
        cd $pwd
}

command=$1
shift
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
'')     ;;
*)
        echo "Unknown command" >&2
        exit 1
        ;;
esac
