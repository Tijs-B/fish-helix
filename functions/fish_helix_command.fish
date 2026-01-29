# FIXME this can't be called in sequence in general case,
# because of unsynchronized `commandline -f` and `commandline -C`

function fish_helix_command
    argparse h/help -- $argv
    or return 1
    if test -n "$_flag_help"
        echo "Helper function to handle modal key bindings mostly outside of insert mode"
        return
    end

    # TODO only single command allowed really yet,
    #     because `commandline -f` queues actions, while `commandline -C` is immediate
    for command in $argv
        set -f count (fish_bind_count -r)
        set -f count_defined $status

        switch $command
            case {move,extend}_char_left
                commandline -C (math max\(0, (commandline -C) - $count\))
                __fish_helix_extend_by_command $command
            case {move,extend}_char_right
                commandline -C (math (commandline -C) + $count)
                __fish_helix_extend_by_command $command

            case char_up
                __fish_helix_char_up $fish_bind_mode $count
            case char_down
                __fish_helix_char_down $fish_bind_mode $count

            case next_word_start
                # https://regex101.com/r/KXrl1x/1
                set -l regex (string join '' \
            '(?:.?\n+|' \
            '[[:alnum:]_](?=[^[:alnum:]_\s])|' \
            '[^[:alnum:]_\s](?=[[:alnum:]_])|' \
            '[^\S\n](?=[\S\n])|)' \
            '((?:[[:alnum:]_]+|[^[:alnum:]_\s]+|)[^\S\n]*)' \
            )
                __fish_helix_next_word $fish_bind_mode $count $regex

            case next_long_word_start
                set -l regex (string join '' \
            '(?:.?\n+|' \
            '[^\S\n](?=[\S\n])|)' \
            '(\S*[^\S\n]*)' \
            )
                __fish_helix_next_word $fish_bind_mode $count $regex

            case next_word_end
                # https://regex101.com/r/Gl0KP2/1
                set -l regex ' (?:
                .?\n+ |
                [[:alnum:]_](?=[^[:alnum:]_]) |
                [^[:alnum:]_\s](?=[[:alnum:]_\s]) | )
            ( [^\S\n]*
                (?: [[:alnum:]_]+ | [^[:alnum:]_\s]+ | ) ) '
                __fish_helix_next_word $fish_bind_mode $count $regex

            case next_long_word_end
                set -l regex ' (?: .?\n+ | \S(?=\s) | )
            ( [^\S\n]* \S* ) '
                __fish_helix_next_word $fish_bind_mode $count $regex

            case prev_word_start
                set -l regex ' ( (?:
                [[:alnum:]_]+ |
                [^[:alnum:]_\s]+ | )
            [^\S\n]* )
            (?: \n+.? |
                (?<=[^[:alnum:]_])[[:alnum:]_] |
                (?<=[[:alnum:]_\s])[^[:alnum:]_\s] | ) '
                __fish_helix_prev_word $fish_bind_mode $count $regex

            case prev_long_word_start
                set -l regex '
            ( \S* [^\S\n]* )
            (?: \n+.? | (?<=\s)\S | ) '
                __fish_helix_prev_word $fish_bind_mode $count $regex

            case till_next_char
                __fish_helix_find_char $fish_bind_mode $count forward-jump-till forward-char
            case find_next_char
                __fish_helix_find_char $fish_bind_mode $count forward-jump
            case till_prev_char
                __fish_helix_find_char $fish_bind_mode $count backward-jump-till backward-char
            case find_prev_char
                __fish_helix_find_char $fish_bind_mode $count backward-jump

            case till_next_cr
                __fish_helix_find_next_cr $fish_bind_mode $count 2
            case find_next_cr
                __fish_helix_find_next_cr $fish_bind_mode $count 1
            case till_prev_cr
                __fish_helix_find_prev_cr $fish_bind_mode $count 1
            case find_prev_cr
                __fish_helix_find_prev_cr $fish_bind_mode $count 0

            case goto_line_start
                commandline -f beginning-of-line
                __fish_helix_extend_by_mode
            case goto_line_end
                __fish_helix_goto_line_end
                __fish_helix_extend_by_mode
            case goto_first_nonwhitespace
                __fish_helix_goto_first_nonwhitespace
                __fish_helix_extend_by_mode

            case goto_file_start
                __fish_helix_goto_line $count
            case goto_line
                if test "$count_defined" = 0 # if true
                    __fish_helix_goto_line $count
                end
            case goto_last_line
                commandline -f end-of-buffer beginning-of-line
                __fish_helix_extend_by_mode

            case insert_mode
                commandline -C (commandline -B)
                set fish_bind_mode insert
                commandline -f end-selection repaint-mode

            case append_mode
                commandline -C (commandline -E)
                set fish_bind_mode insert
                commandline -f end-selection repaint-mode

            case prepend_to_line
                __fish_helix_goto_first_nonwhitespace
                set fish_bind_mode insert
                commandline -f end-selection repaint-mode

            case append_to_line
                set fish_bind_mode insert
                commandline -f end-selection end-of-line repaint-mode

            case delete_selection
                commandline -f kill-selection begin-selection
            case delete_selection_noyank
                __fish_helix_delete_selection

            case yank
                __fish_helix_yank
            case paste_before
                __fish_helix_paste_before "commandline -f yank"
            case paste_after
                __fish_helix_paste_after "commandline -f yank"
            case replace_selection
                __fish_helix_replace_selection "$fish_killring[1]" true

            case paste_before_clip
                __fish_helix_paste_before fish_clipboard_paste
            case paste_after_clip
                __fish_helix_paste_after fish_clipboard_paste --clip
            case replace_selection_clip
                __fish_helix_replace_selection "" fish_clipboard_paste --clip

            case select_all
                commandline -f beginning-of-buffer begin-selection end-of-buffer end-of-line backward-char

            case extend_line_below
                __fish_helix_extend_line_below

            case trim_selections
                __fish_helix_trim_selections

            case join_lines
                __fish_helix_join_lines $count

            case '*'
                echo "[fish-helix]" Unknown command $command >&2
        end
    end
end

function __fish_helix_extend_by_command -a piece
    if not string match -qr extend_ $piece
        commandline -f begin-selection
    end
end

function __fish_helix_extend_by_mode
    if test $fish_bind_mode = default
        commandline -f begin-selection
    end
end

function __fish_helix_find_char -a mode count fish_cmdline till
    # FIXME don't reset selection if N/A
    if test $mode = default
        commandline -f begin-selection
    end
    commandline -f $till $fish_cmdline
    if test $count -gt 1
        for i in (seq 2 $count)
            commandline -f $till repeat-jump
        end
    end
end

function __fish_helix_find_next_cr -a mode count skip
    set -l cursor (commandline -C)
    commandline | # Include endling newline intentionally
        # Skip until cursor:
        sed -z 's/^.\{'(math $cursor + $skip)'\}\(.*\)$/\\1/' |
        # Count characters up to the target newline:
        sed -z 's/^\(\([^\\n]*\\n\)\{0,'$count'\}\).*/\\1/' |
        read -zl chars

    if test $mode = default -a -n "$chars"
        commandline -f begin-selection
    end
    set -l chars_len (string length -- "$chars")
    if test $chars_len -gt 0
        for i in (seq 1 $chars_len)
            commandline -f forward-char
        end
    end
end

function __fish_helix_find_prev_cr -a mode count skip
    set -l cursor (commandline -C)
    commandline --cut-at-cursor |
        sed -z 's/.\{'$skip'\}\n$//' |
        read -zl buffer

    echo -n $buffer |
        # Drop characters up to the target newline:
        sed -z 's/\(\(\\n[^\\n]*\)\{0,'$count'\}\)$//' |
        read -zl chars
    set -l n_chars (math (string length -- "$buffer") - (string length -- "$chars"))

    if test $mode = default -a $n_chars != 0
        commandline -f begin-selection
    end
    if test $n_chars -gt 0
        for i in (seq 1 $n_chars)
            commandline -f backward-char
        end
    end
end

function __fish_helix_goto_line_end
    # Get the current command line content and store it in a variable
    set current_cmd (commandline)

    # Use `string trim` to handle empty lines effectively
    if test -z (string trim -- "$current_cmd")
        return
    end

    # Move to the end of the line and then back by one character
    commandline -f end-of-line backward-char
end

function __fish_helix_goto_first_nonwhitespace
    # Store the current command line content in a variable
    set current_cmd (commandline)

    # Check if the trimmed command line is empty
    if test -z (string trim -- "$current_cmd")
        return
    end

    # Find the position of the first non-whitespace character
    set -l first_nonws_pos (string match -rn '\S' -- "$current_cmd" | cut -d' ' -f1)

    if test -n "$first_nonws_pos"
        # Move cursor to that position (subtract 1 because commandline -C is 0-based)
        commandline -C (math "$first_nonws_pos" - 1)
    end
end

function __fish_helix_goto_line -a number
    set -l lines (math min\($number, (commandline | wc -l)\))
    commandline -f beginning-of-buffer
    if test $lines -gt 1
        for i in (seq 2 $lines)
            commandline -f down-line
        end
    end
    __fish_helix_extend_by_mode
end

function __fish_helix_char_up -a mode count
    if commandline --paging-mode && not commandline --search-mode
        if test $count -gt 0
            for i in (seq 1 $count)
                commandline -f up-line
            end
        end
        return
    end
    set -l line (commandline -L)
    if commandline --search-mode || test $line = 1
        set -l hist_count (math "min($count, "(count $history)")")
        if test $hist_count -gt 0
            for i in (seq 1 $hist_count)
                commandline -f history-search-backward
            end
        end
        return
    end
    set -l count (math "min($count, $line-1)")
    if test $count -gt 0
        for i in (seq 1 $count)
            commandline -f up-line
        end
    end
    __fish_helix_extend_by_mode
end

function __fish_helix_char_down -a mode count
    if commandline --paging-mode && not commandline --search-mode
        if test $count -gt 0
            for i in (seq 1 $count)
                commandline -f down-line
            end
        end
        return
    end
    set -l line (commandline -L)
    set -l total (count (commandline))
    if commandline --search-mode || test $line = $total
        set -l hist_count (math "min($count, "(count $history)")")
        if test $hist_count -gt 0
            for i in (seq 1 $hist_count)
                commandline -f history-search-forward
            end
        end
        return
    end
    set -l count (math "min($count, $total - $line)")
    if test $count -gt 0
        for i in (seq 1 $count)
            commandline -f down-line
        end
    end
    __fish_helix_extend_by_mode
end

function __fish_helix_next_word -a mode count regex
    set -f cursor (commandline -C)
    commandline |
        perl -e '
        use open qw(:std :utf8);
        do { local $/; substr <>, '$cursor' } =~ m/(?:'$regex'){0,'$count'}/ux;
        print $-[1], " ", $+[1];' |
        read -f left right
    test "$left" = "$right" && return
    if test $mode = default
        commandline -C (math $cursor + $left)
        commandline -f begin-selection
        set -l num_moves (math $right - $left - 1)
        if test $num_moves -gt 0
            for i in (seq 1 $num_moves)
                commandline -f forward-char
            end
        end
    else
        commandline -C (math $cursor + $right - 1)
    end
end

function __fish_helix_prev_word -a mode count regex
    set -f left (math (commandline -C) + 1)
    set -f updated 0
    for i in (seq 1 $count)
        commandline |
            perl -e '
            use open qw(:std :utf8);
            do { local $/; substr <>, 0, '$left' } =~ /(?:'$regex')$/ux;
            print $-[1], " ", $+[1];' |
            read -l l r
        test "$l" = "$r" -o "$l" = 0 -a "$r" = 1 && break
        set -f left $l
        set -f right $r
        set -f updated 1
    end
    test $updated -eq 0; and return
    if test $mode = default
        commandline -C (math $right - 1)
        commandline -f begin-selection
        set -l num_moves (math $right - $left - 1)
        if test $num_moves -gt 0
            for i in (seq 1 $num_moves)
                commandline -f backward-char
            end
        end
    else
        commandline -C (math $left)
    end
end

function __fish_helix_delete_selection
    set start (commandline -B)
    set end (commandline -E)
    commandline |
        sed -zE 's/^(.{'$start'})(.{0,'(math $end - $start)'})(.*)\\n$/\\1\\3/' |
        read -l result

    commandline "$result"
    commandline -C $start
    commandline -f begin-selection
end

function __fish_helix_yank
    set -l end (commandline -E)
    set -l cursor (commandline -C)
    commandline -f kill-selection yank backward-char

    set -l num_moves (math $end - $cursor - 1)
    if test $num_moves -gt 0
        for i in (seq 1 $num_moves)
            commandline -f backward-char
        end
    end
end

function __fish_helix_paste_before -a cmd_paste
    set -l cmd_paste (string split " " $cmd_paste)
    set -l cursor (commandline -C)
    set -l start (commandline -B)
    set -l end (commandline -E)
    commandline -C $start
    $cmd_paste
    commandline -f begin-selection
    set -l num_moves (math $end - $start - 1)
    if test $num_moves -gt 0
        for i in (seq 1 $num_moves)
            commandline -f forward-char
        end
    end
    if test $cursor = $start
        commandline -f swap-selection-start-stop
    end
end

function __fish_helix_paste_after -a cmd_paste
    set -l cmd_paste (string split " " $cmd_paste)
    set -l cursor (commandline -C)
    set -l start (commandline -B)
    set -l end (commandline -E)
    commandline -C $end
    $cmd_paste

    if test "$argv[2]" = --clip
        commandline -C (math $end - 1)
    else
        set -l killring_len (string length "$fish_killring[1]")
        if test $killring_len -ge 0
            for i in (seq 0 $killring_len)
                commandline -f backward-char
            end
        end
    end
    commandline -f begin-selection
    set -l num_moves (math $end - $start - 1)
    if test $num_moves -gt 0
        for i in (seq 1 $num_moves)
            commandline -f backward-char
        end
    end
    if test $cursor != $start
        commandline -f swap-selection-start-stop
    end
end

function __fish_helix_replace_selection -a replacement cmd_paste
    set -l cmd_paste (string split " " $cmd_paste)
    set cursor (commandline -C)
    set start (commandline -B)
    set end (commandline -E)
    set length (math $end - $start)
    set escaped_replacement (string escape --style=regex "$replacement")

    string replace --all --regex '^(.{'$start'})(.{0,'$length'})(.*)\\n$' '\\1'"$escaped_replacement"'\\3' |
        read -l result

    commandline "$result"
    commandline -C $start
    $cmd_paste

    if test "$argv[3]" = --clip
        commandline -f backward-char begin-selection
        set -l current_pos (commandline -C)
        set -l num_moves (math $current_pos - $start - 2)
        if test $num_moves -gt 0
            for i in (seq 1 $num_moves)
                commandline -f backward-char
            end
        end
        if test $cursor != $start
            commandline -f swap-selection-start-stop
        end
    else
        commandline -f begin-selection
        set -l replacement_len (string length "$replacement")
        if test $replacement_len -gt 1
            for i in (seq 2 $replacement_len)
                commandline -f forward-char
            end
        end
        if test $cursor = $start
            commandline -f swap-selection-start-stop
        end
    end
end

function __fish_helix_extend_line_below
    set -l sel_start (commandline -B)
    set -l sel_end (commandline -E)
    set -l cursor (commandline -C)

    set -l is_line_selection 0
    if test $sel_start -ge 0
        set -l c (commandline -C)
        commandline -C $sel_start
        set -l start_pos (commandline -C)
        commandline -f beginning-of-line
        if test "$start_pos" = (commandline -C)
            commandline -C $sel_end
            set -l end_pos (commandline -C)
            commandline -f end-of-line
            if test "$end_pos" = (commandline -C)
                set is_line_selection 1
            end
        end
        commandline -C $c
    end

    if test $is_line_selection = 1
        commandline -C $sel_end
        commandline -f down-line
        commandline -f end-of-line
    else
        if test $sel_start -lt 0
            set sel_start $cursor
            set sel_end $cursor
        end
        commandline -C $sel_start
        commandline -f beginning-of-line
        commandline -f begin-selection
        commandline -C $sel_end
        commandline -f end-of-line
    end
end

function __fish_helix_join_lines -a count
    set -l text (commandline)
    set -l cursor (commandline -C)

    # Find how many lines we have
    set -l total_lines (echo -n "$text" | perl -e 'local $/; my $t = <STDIN>; print scalar(() = $t =~ /\n/g) + 1')

    # Get current line number
    set -l current_line (commandline -L)

    # Can't join if we're on the last line
    if test $current_line -ge $total_lines
        return
    end

    # Limit count to available lines
    set -l max_joins (math $total_lines - $current_line)
    if test $count -gt $max_joins
        set count $max_joins
    end

    # Perform the join(s) using perl
    set -l result (echo -n "$text" | perl -e '
        use open qw(:std :utf8);
        my $current_line = $ARGV[0];
        my $count = $ARGV[1];
        local $/;
        my $text = <STDIN>;
        my @lines = split /\n/, $text, -1;

        # Join count times starting from current line (1-indexed to 0-indexed)
        my $idx = $current_line - 1;
        for (my $i = 0; $i < $count && $idx < $#lines; $i++) {
            # Remove trailing whitespace from current line
            $lines[$idx] =~ s/\s*$//;
            # Remove leading whitespace from next line
            $lines[$idx + 1] =~ s/^\s*//;
            # Join with space (unless next line is empty)
            if (length($lines[$idx + 1]) > 0) {
                $lines[$idx] .= " " . $lines[$idx + 1];
            }
            # Remove the joined line
            splice(@lines, $idx + 1, 1);
        }

        print join("\n", @lines);
    ' "$current_line" "$count")

    commandline "$result"

    # Position cursor at the join point (end of original line content)
    # and set selection on the space
    commandline -f end-of-line
    commandline -f begin-selection
end

function __fish_helix_select_pair -a open_char close_char select_mode
    set -l cursor (commandline -C)
    set -l text (commandline)
    set -l text_len (string length -- "$text")

    # If text is empty, nothing to do
    if test $text_len -eq 0
        return
    end

    set -l open_pos -1
    set -l close_pos -1

    if test "$open_char" = "$close_char"
        # Symmetric character (quotes, backticks)
        # Find nearest open before or at cursor, and close after cursor
        # Use perl for reliable string handling
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $char = $ARGV[0];
            my $cursor = $ARGV[1];
            local $/;
            my $text = <STDIN>;
            my @positions;
            my $pos = 0;
            while (($pos = index($text, $char, $pos)) != -1) {
                push @positions, $pos;
                $pos++;
            }
            # Find pair that encloses cursor
            for (my $i = 0; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            # Try odd pairing if even failed
            for (my $i = 1; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            print "-1 -1\n";
        ' "$open_char" "$cursor")
        echo $positions | read open_pos close_pos
    else
        # Paired characters - handle nesting
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $open_char = $ARGV[0];
            my $close_char = $ARGV[1];
            my $cursor = $ARGV[2];
            local $/;
            my $text = <STDIN>;
            my $len = length($text);

            # Search backwards from cursor for unmatched open
            my $depth = 0;
            my $open_pos = -1;
            for (my $i = $cursor; $i >= 0; $i--) {
                my $c = substr($text, $i, 1);
                if ($c eq $close_char) {
                    $depth++;
                } elsif ($c eq $open_char) {
                    if ($depth == 0) {
                        $open_pos = $i;
                        last;
                    }
                    $depth--;
                }
            }

            if ($open_pos == -1) {
                print "-1 -1\n";
                exit;
            }

            # Search forwards from open_pos for matching close
            $depth = 0;
            my $close_pos = -1;
            for (my $i = $open_pos; $i < $len; $i++) {
                my $c = substr($text, $i, 1);
                if ($c eq $open_char) {
                    $depth++;
                } elsif ($c eq $close_char) {
                    $depth--;
                    if ($depth == 0) {
                        $close_pos = $i;
                        last;
                    }
                }
            }

            print "$open_pos $close_pos\n";
        ' "$open_char" "$close_char" "$cursor")
        echo $positions | read open_pos close_pos
    end

    # Check if we found a valid pair
    if test "$open_pos" = "-1" -o "$close_pos" = "-1"
        return
    end

    # Set selection based on mode
    if test "$select_mode" = inner
        # Select inside the pair (excluding delimiters)
        set -l start (math $open_pos + 1)
        set -l end $close_pos
        # If inner is empty, still position cursor there
        if test $start -ge $end
            commandline -C $start
            commandline -f begin-selection
            return
        end
        commandline -C $start
        commandline -f begin-selection
        set -l num_moves (math $end - $start - 1)
        if test $num_moves -gt 0
            for i in (seq 1 $num_moves)
                commandline -f forward-char
            end
        end
    else
        # Select around the pair (including delimiters)
        commandline -C $open_pos
        commandline -f begin-selection
        set -l num_moves (math $close_pos - $open_pos)
        if test $num_moves -gt 0
            for i in (seq 1 $num_moves)
                commandline -f forward-char
            end
        end
    end
end

function __fish_helix_delete_pair -a open_char close_char
    set -l cursor (commandline -C)
    set -l text (commandline)
    set -l text_len (string length -- "$text")

    # If text is empty, nothing to do
    if test $text_len -eq 0
        return
    end

    set -l open_pos -1
    set -l close_pos -1

    if test "$open_char" = "$close_char"
        # Symmetric character (quotes, backticks)
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $char = $ARGV[0];
            my $cursor = $ARGV[1];
            local $/;
            my $text = <STDIN>;
            my @positions;
            my $pos = 0;
            while (($pos = index($text, $char, $pos)) != -1) {
                push @positions, $pos;
                $pos++;
            }
            # Find pair that encloses cursor
            for (my $i = 0; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            # Try odd pairing if even failed
            for (my $i = 1; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            print "-1 -1\n";
        ' "$open_char" "$cursor")
        echo $positions | read open_pos close_pos
    else
        # Paired characters - handle nesting
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $open_char = $ARGV[0];
            my $close_char = $ARGV[1];
            my $cursor = $ARGV[2];
            local $/;
            my $text = <STDIN>;
            my $len = length($text);

            # Search backwards from cursor for unmatched open
            my $depth = 0;
            my $open_pos = -1;
            for (my $i = $cursor; $i >= 0; $i--) {
                my $c = substr($text, $i, 1);
                if ($c eq $close_char) {
                    $depth++;
                } elsif ($c eq $open_char) {
                    if ($depth == 0) {
                        $open_pos = $i;
                        last;
                    }
                    $depth--;
                }
            }

            if ($open_pos == -1) {
                print "-1 -1\n";
                exit;
            }

            # Search forwards from open_pos for matching close
            $depth = 0;
            my $close_pos = -1;
            for (my $i = $open_pos; $i < $len; $i++) {
                my $c = substr($text, $i, 1);
                if ($c eq $open_char) {
                    $depth++;
                } elsif ($c eq $close_char) {
                    $depth--;
                    if ($depth == 0) {
                        $close_pos = $i;
                        last;
                    }
                }
            }

            print "$open_pos $close_pos\n";
        ' "$open_char" "$close_char" "$cursor")
        echo $positions | read open_pos close_pos
    end

    # Check if we found a valid pair
    if test "$open_pos" = "-1" -o "$close_pos" = "-1"
        return
    end

    # Delete the pair characters and set selection on the inner content
    # Build new text: before_open + inner_content + after_close
    set -l before (string sub -l $open_pos -- "$text")
    set -l inner (string sub -s (math $open_pos + 2) -l (math $close_pos - $open_pos - 1) -- "$text")
    set -l after (string sub -s (math $close_pos + 2) -- "$text")

    commandline "$before$inner$after"

    # Set selection on the inner content (now at open_pos)
    set -l inner_len (string length -- "$inner")
    if test $inner_len -eq 0
        # Empty inner, just position cursor
        commandline -C $open_pos
        commandline -f begin-selection
    else
        commandline -C $open_pos
        commandline -f begin-selection
        if test $inner_len -gt 1
            for i in (seq 1 (math $inner_len - 1))
                commandline -f forward-char
            end
        end
    end
end

function __fish_helix_replace_pair -a from_open from_close to_open to_close
    set -l cursor (commandline -C)
    set -l text (commandline)
    set -l text_len (string length -- "$text")

    # If text is empty, nothing to do
    if test $text_len -eq 0
        return
    end

    set -l open_pos -1
    set -l close_pos -1

    if test "$from_open" = "$from_close"
        # Symmetric character (quotes, backticks)
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $char = $ARGV[0];
            my $cursor = $ARGV[1];
            local $/;
            my $text = <STDIN>;
            my @positions;
            my $pos = 0;
            while (($pos = index($text, $char, $pos)) != -1) {
                push @positions, $pos;
                $pos++;
            }
            # Find pair that encloses cursor
            for (my $i = 0; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            # Try odd pairing if even failed
            for (my $i = 1; $i < $#positions; $i += 2) {
                my $open = $positions[$i];
                my $close = $positions[$i + 1];
                if (defined $close && $open <= $cursor && $cursor <= $close) {
                    print "$open $close\n";
                    exit;
                }
            }
            print "-1 -1\n";
        ' "$from_open" "$cursor")
        echo $positions | read open_pos close_pos
    else
        # Paired characters - handle nesting
        set -l positions (echo -n "$text" | perl -e '
            use open qw(:std :utf8);
            my $open_char = $ARGV[0];
            my $close_char = $ARGV[1];
            my $cursor = $ARGV[2];
            local $/;
            my $text = <STDIN>;
            my $len = length($text);

            # Search backwards from cursor for unmatched open
            my $depth = 0;
            my $open_pos = -1;
            for (my $i = $cursor; $i >= 0; $i--) {
                my $c = substr($text, $i, 1);
                if ($c eq $close_char) {
                    $depth++;
                } elsif ($c eq $open_char) {
                    if ($depth == 0) {
                        $open_pos = $i;
                        last;
                    }
                    $depth--;
                }
            }

            if ($open_pos == -1) {
                print "-1 -1\n";
                exit;
            }

            # Search forwards from open_pos for matching close
            $depth = 0;
            my $close_pos = -1;
            for (my $i = $open_pos; $i < $len; $i++) {
                my $c = substr($text, $i, 1);
                if ($c eq $open_char) {
                    $depth++;
                } elsif ($c eq $close_char) {
                    $depth--;
                    if ($depth == 0) {
                        $close_pos = $i;
                        last;
                    }
                }
            }

            print "$open_pos $close_pos\n";
        ' "$from_open" "$from_close" "$cursor")
        echo $positions | read open_pos close_pos
    end

    # Check if we found a valid pair
    if test "$open_pos" = "-1" -o "$close_pos" = "-1"
        return
    end

    # Replace the pair characters
    # Build new text: before_open + to_open + inner + to_close + after_close
    set -l before (string sub -l $open_pos -- "$text")
    set -l inner (string sub -s (math $open_pos + 2) -l (math $close_pos - $open_pos - 1) -- "$text")
    set -l after (string sub -s (math $close_pos + 2) -- "$text")

    commandline "$before$to_open$inner$to_close$after"

    # Set selection to include the new delimiters
    set -l inner_len (string length -- "$inner")
    set -l selection_len (math $inner_len + 2)
    commandline -C $open_pos
    commandline -f begin-selection
    for i in (seq 1 (math $selection_len - 1))
        commandline -f forward-char
    end
end

function __fish_helix_surround_selection -a open_char close_char
    set -l sel_start (commandline -B)
    set -l sel_end (commandline -E)
    set -l cursor (commandline -C)

    # If no selection, nothing to surround
    if test $sel_start -lt 0
        return
    end

    # Get the full text
    set -l text (commandline)

    # Extract the parts: before selection, selection, after selection
    # string sub uses 1-based indexing
    set -l before (string sub -l $sel_start -- "$text")
    set -l selected (string sub -s (math $sel_start + 1) -l (math $sel_end - $sel_start) -- "$text")
    set -l after (string sub -s (math $sel_end + 1) -- "$text")

    # Build new text with surround characters
    commandline "$before$open_char$selected$close_char$after"

    # Set new selection to include the surround characters
    # New selection: from sel_start to sel_end + 2 (for the two added chars)
    # Selection starts at the opening char
    commandline -C $sel_start
    commandline -f begin-selection

    # Move forward to include: open_char + selected + close_char
    # That's (sel_end - sel_start) + 2 - 1 = sel_end - sel_start + 1 forward moves
    set -l new_length (math $sel_end - $sel_start + 1)
    for i in (seq 1 $new_length)
        commandline -f forward-char
    end

    # Preserve cursor direction (if cursor was at start, swap)
    if test $cursor -eq $sel_start
        commandline -f swap-selection-start-stop
    end
end

function __fish_helix_trim_selections
    set -l sel_start (commandline -B)
    set -l sel_end (commandline -E)
    set -l cursor (commandline -C)

    # If no selection, nothing to trim
    if test $sel_start -lt 0
        return
    end

    # Get the full text and extract selection
    set -l text (commandline)
    set -l length (math $sel_end - $sel_start)

    # Extract selected text (string sub uses 1-based indexing)
    set -l selected (string sub -s (math $sel_start + 1) -l $length -- "$text")

    # If selection is empty, nothing to do
    if test -z "$selected"
        return
    end

    # Find leading whitespace count
    set -l leading_match (string match -r '^\s+' -- "$selected")
    set -l leading_ws (string length -- "$leading_match")

    # Find trailing whitespace count
    set -l trailing_match (string match -r '\s+$' -- "$selected")
    set -l trailing_ws (string length -- "$trailing_match")

    # If nothing to trim, return
    if test $leading_ws -eq 0 -a $trailing_ws -eq 0
        return
    end

    # Check if entire selection is whitespace (leading + trailing overlap)
    if test (math $leading_ws + $trailing_ws) -ge $length
        return
    end

    # Calculate new selection length
    set -l new_length (math $length - $leading_ws - $trailing_ws)
    set -l new_start (math $sel_start + $leading_ws)

    # Set the new selection using count-based loop
    commandline -C $new_start
    commandline -f begin-selection
    if test $new_length -gt 1
        for i in (seq 1 (math $new_length - 1))
            commandline -f forward-char
        end
    end

    # Preserve cursor direction (if cursor was at start, swap)
    if test $cursor -eq $sel_start
        commandline -f swap-selection-start-stop
    end
end
