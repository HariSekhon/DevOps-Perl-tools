#!/usr/bin/env bash
#
#  Author: Vladimir Zlatkin (Hortonworks)
#
#  https://community.hortonworks.com/articles/16846/how-to-identify-what-is-consuming-space-in-hdfs.html
#

max_depth=5

largest_root_dirs="$(hdfs dfs -du -s '/*' | sort -nr | perl -ane 'print "$F[1] "')"

printf "%15s  %s\n" "bytes" "directory"
for ld in $largest_root_dirs; do
    printf "%15.0f  %s\n" "$(hdfs dfs -du -s "$ld" | cut -d' ' -f1)" "$ld"
    all_dirs="$(hdfs dfs -ls -R "$ld" | grep -E '^dr........' | perl -ane "scalar(split('/',\$_)) <= $max_depth && print \"\$F[7]\n\"" )"

    for d in $all_dirs; do
        line="$(hdfs dfs -du -s "$d")"
        size="$(cut -d' ' -f1 <<< "$line")"
        parent_dir=${d%/*}
        child=${d##*/}
        if [ -n "$parent_dir" ]; then
            leading_dirs=$(perl -pe 's/./-/g; s/^.(.+)$/\|$1/' <<< "$parent_dir")
            d=${leading_dirs}/$child
        fi
        printf "%15.0f  %s\n" "$size" "$d"
    done
done
