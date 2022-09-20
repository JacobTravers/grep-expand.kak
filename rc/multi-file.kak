decl -hidden str multi_file_home %sh{ dirname $(dirname "$kak_source") }

# Commands

def -params .. \
    -override \
    -docstring 'Create grep-expand file from grep results' \
    grep-expand \
%{
    require-module grep-expand-colors
    eval %sh{
        # Setup fifos
        work_dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak.XXXXXXXX)
        mkdir -p "$work_dir"
        mkfifo "$work_dir/input"
        mkfifo "$work_dir/output"

        # Spawn script
        (
            "$kak_opt_multi_file_home/scripts/grep_expand.py" $@ \
                <"$work_dir/input" \
                >"$work_dir/output"
        ) >/dev/null 2>&1 </dev/null &

        # Read output to client, write input
        printf %s "
            eval %{
                edit! -fifo '$work_dir/output' *grep-expand*
                set buffer filetype grep-expand
                hook -always -once buffer BufCloseFifo .* %{
                    nop %sh{ rm -r '$work_dir' }
                    exec -draft gjd
                    grep-expand-close-empty '$kak_client'
                }
            }
            eval -buffer '$kak_bufname' %{
                write '$work_dir/input'
            }
        "
    }
}

def -override \
    -docstring 'Write and close grep-expand' \
    grep-expand-write \
%{
    grep-expand-ensure-buffer-exists

    eval %sh{
        # Setup fifos
        work_dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak.XXXXXXXX)
        mkdir -p "$work_dir"
        mkfifo "$work_dir/input"
        mkfifo "$work_dir/output"

        # Spawn script, close buffers on success
        (
            "$kak_opt_multi_file_home/scripts/grep_expand_write.py" \
                <"$work_dir/input" \
                >"$work_dir/output" 2>&1

            if [ $? = 0 ]; then
                printf %s "
                    try %{ db *grep-expand* }
                    try %{ db *grep-expand-output* }
                    try %{ db *grep-expand-review* }
                    eval -client '$kak_client' %{
                        echo -markup {Information}All changes applied
                    }
                " | kak -p "$kak_session"
            else
                printf %s "
                    eval -client '$kak_client' %{
                        echo -markup {Error}Not all changes were applied
                    }
                " | kak -p "$kak_session"
            fi
        ) >/dev/null 2>&1 </dev/null &

        # Read output to client, write input
        printf %s "
            eval -try-client '$kak_opt_toolsclient' %{
                edit! -fifo '$work_dir/output' *grep-expand-output*
                hook -always -once buffer BufCloseFifo .* %{
                    nop %sh{ rm -r '$work_dir' }
                }
            }
            eval -buffer *grep-expand* %{
                write '$work_dir/input'
            }
        "
    }
}

def -override \
    -docstring 'Review changes in grep-expand' \
    grep-expand-review \
%{
    grep-expand-ensure-buffer-exists

    eval %sh{
        # Setup fifos
        work_dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak.XXXXXXXX)
        mkdir -p "$work_dir"
        mkfifo "$work_dir/input"
        mkfifo "$work_dir/output"

        # Spawn script, close buffers on success
        (
            "$kak_opt_multi_file_home/scripts/grep_expand_write.py" --dry-run \
                <"$work_dir/input" \
                >"$work_dir/output" 2>&1

            if [ $? = 0 ]; then
                printf %s "
                    eval -client '$kak_client' %{
                        echo -markup {Information}All changes can be applied
                    }
                " | kak -p "$kak_session"
            else
                printf %s "
                    eval -client '$kak_client' %{
                        echo -markup {Error}Not all changes can be applied
                    }
                " | kak -p "$kak_session"
            fi
        ) >/dev/null 2>&1 </dev/null &

        # Read output to client, write input
        printf %s "
            eval -try-client '$kak_opt_toolsclient' %{
                edit! -fifo '$work_dir/output' *grep-expand-review*
                set buffer filetype diff
                hook -always -once buffer BufCloseFifo .* %{
                    nop %sh{ rm -r '$work_dir' }
                }
            }
            eval -buffer *grep-expand* %{
                write '$work_dir/input'
            }
        "
    }
}

# Utility commands

def -hidden \
    -override \
    -params 1 \
    grep-expand-close-empty \
%{
    try %{
        exec -draft <%> s (?S). <ret>
    } catch %{
        db
        eval -client %arg{1} %{
            echo -markup {Error}No grep lines detected
        }
    }
}

def -hidden \
    -override \
    grep-expand-ensure-buffer-exists \
%{
    try %{
        eval -buffer *grep-expand* ''
    } catch %{
        fail 'No *grep-expand* buffer'
    }
}

# Colors

provide-module grep-expand-colors %§

    try %{ rmhl shared/grep-expand }
    try %{ rmhooks global grep-expand-highlight }

    addhl shared/grep-expand regions

    addhl shared/grep-expand/default default-region \
        regex "^@@@[^\n]*@@@$" 0:Information

    def -hidden \
        -params 2 \
        -override \
        grep-expand-hl-lang \
    %{
        eval %sh{
            printf '
                addhl shared/grep-expand/%s region \
                    "(?Si)^@@@ .*%s \d+,\d+ \S+ \S+ @@@$" \
                    "^(?=@@@ )" \
                    regions
            ' "$1" "$2"

            printf '
                addhl shared/grep-expand/%s/header region \
                    "(?S)^@@@.*@@@$" $ \
                    fill Information
            ' "$1"

            printf '
                addhl shared/grep-expand/%s/body default-region \
                    ref %s
            ' "$1" "$1"
        }
    }

    grep-expand-hl-lang objc \.(c|cc|cl|cpp|h|hh|hpp|m|mm)
    grep-expand-hl-lang cabal \.cabal
    grep-expand-hl-lang clojure \.(clj|cljc|cljs|cljx|edn)
    grep-expand-hl-lang coffee \.coffee
    grep-expand-hl-lang css .*\.css
    grep-expand-hl-lang d .*\.d
    grep-expand-hl-lang dockerfile dockerfile
    grep-expand-hl-lang fish \.fish
    grep-expand-hl-lang go \.go
    grep-expand-hl-lang haskell \.hs
    grep-expand-hl-lang html \.html?
    grep-expand-hl-lang ini \.ini
    grep-expand-hl-lang java \.java
    grep-expand-hl-lang typescript \.m?[jt]sx?
    grep-expand-hl-lang json \.json
    grep-expand-hl-lang julia \.jl
    grep-expand-hl-lang kakrc (\.kak|kakrc)
    grep-expand-hl-lang latex \.(tex|cls|sty|dtx)
    grep-expand-hl-lang lua \.lua
    grep-expand-hl-lang makefile (makefile|\.mk|\.make)
    grep-expand-hl-lang markdown \.(markdown|md|mkd)
    grep-expand-hl-lang perl \.(t|p[lm])
    grep-expand-hl-lang python \.py
    grep-expand-hl-lang ruby \.rb
    grep-expand-hl-lang rust \.rs
    grep-expand-hl-lang sass \.sass
    grep-expand-hl-lang scala \.scala
    grep-expand-hl-lang scss \.scss
    grep-expand-hl-lang sh \.(z|ba|c|k|mk)?sh(rc|_profile)?
    grep-expand-hl-lang swift \.swift
    grep-expand-hl-lang toml \.toml
    grep-expand-hl-lang yaml \.ya?ml
    grep-expand-hl-lang sql \.sql

    hook -group grep-expand-highlight global WinSetOption filetype=grep-expand %{
        addhl window/grep-expand ref grep-expand
        hook -once -always window WinSetOption filetype=.* %{
            rmhl window/grep-expand
        }
    }

§ # module grep-expand-colors
