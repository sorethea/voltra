#!/bin/sh
# Voltra · Supervisor event listener — logs process state changes

while read -r line; do
    case "$line" in
        "ver:3.0 server:supervisor"*)
            while read -r header && [ "$header" != "ENDOFPROCESS" ]; do
                case "$header" in
                    processname:*|from_state:*|to_state:*|pid:*)
                        printf '%s ' "$header"
                        ;;
                esac
            done
            printf '\n'
            ;;
    esac
    echo "RESULT 2"
    echo "OK"
done
