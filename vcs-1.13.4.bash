#!/usr/bin/env bash
#
# $Rev: 688 $ $Date: 2019-11-26 12:01:45 +0100 (Tue, 26 Nov 2019) $
#
# vcs
# Video Contact Sheet *NIX: Generates contact sheets (previews) of videos
#
# Copyright (C) 2007-2019 Toni Corvera
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
#
# Author: Toni Corvera <outlyer@gmail.com>
#
# (Note: The references that used to be here have been moved to
#+       <http://p.outlyer.net/dox/vcs:devel:references>)
#
# The full changelog can be found at <http://p.outlyer.net/vcs/files/CHANGELOG>

declare -r VERSION="1.13.4"
declare -r RELEASE=1
declare -ri PRERELEASE=2
[ "$RELEASE" -eq 1 ] || declare -r SUBVERSION="-pre.${PRERELEASE}"

set -e

# GAWK 3.1.3 to 3.1.5 print decimals (with printf) according to locale (i.e.
#+decimal comma separator in some locales, which is apparently POSIX correct).
#+Older and newer versions, though, need either POSIXLY_CORRECT to be set (even
#+be empty), --posix or --use-lc-numeric to honour locale.
# MAWK appears to always use dots.
# Info: <http://www.gnu.org/manual/gawk/html_node/Conversion.html>
#export POSIXLY_CORRECT=1 # Immitate behaviour in newer gawk
export LC_NUMERIC=C
# All output from tools is either removed or parsed.
# Standardise on the C locale.
export LANG=C
export LC_COLLATE=C # Ensure collation (e.g. tr a-z A-Z) works as expected

# Fail soon if this version of bash is too old for the syntax, don't expose bash to the newer
# syntax
# See the "Bash syntax notes" section for details
[ "$BASH_VERSINFO" ] && {
	# Absolute minimum right now is 3.1
	if [ "${BASH_VERSINFO[0]}" -lt 3 ] ||
		[ "${BASH_VERSINFO[0]}" -eq 3 -a "${BASH_VERSINFO[1]}" -lt 1 ]; then
			echo "Bash 3.1 or higher is required" >&2
			exit 1
	fi
}

# {{{ # TO-DO
# * [[x1]] Find out why the order of ffmpeg arguments breaks some files.
# * Change default DVD_TITLE to 0
# * Deprecation schedule:
#     DEPRECATED FROM | EXPECTED REMOVAL | DESCRIPTION
#   ------------------|------------------|------------------------------------------------------
#       1.12              1.14             Old names for settings renamed in 1.12.
#                                           output_format, plain_messages, th_height,
#                                           hpad, font_mincho
#                                          In 1.13 the new names start to be used internally.
#   --------------------------------------------------------------------------------------------
#       1.13              1.14             --end_offset  -> --end-offset
#       1.13              1.14             auto-loading ./vcs.conf (lesser version of profiles)
#                                             -C :pwd will stay
#   --------------------------------------------------------------------------------------------
#          ?               ?+1             decoder. Replaced by capturer, the syntax changes
#          ?               ?+1             --funky       -> --profile
# * Variables cleanup:
#   Variables will use a more uniform scheme, with prefixes where appropriate:
#   - INTERNAL_*: Used internally to adapt messages and the like to the input
#   - UNDFLAG_*: Undocumented flags. Used internally to keep track of undocumented modes (-Z)
#   - USR_*: Holds values of variables as set by the user, either from overrides or from the
#            command-line.
#            implementation
#   - Global variables will be capitalised while local variables will be lowercase
#   - Setting names (configuration file variables) will be case insensitive, but always
#     displayed and documented in lowercase
# * Optimisations:
#   - Reduce the number of forks/subshells
# * Portability notes
#   - 'sed -r' is not portable, works in GNU, FreeBSD equivalent -E
#   - 'grep -o' is not portable, works in GNU and FreeBSD
#      Alternatives:
#      > One match per line:
#        $ sed -n -e 's/.*\(SEARCH\).*/\1/gp
#      > Multiple matches per line: (like grep -o)
#        $ sed -n -e 's/\(SEARCH\)/\1\
#        /gp' | sed -e 's/.*\(SEARCH\).*/\1/' -e '/SEARCH/!d'
#      The p flag ONLY prints IF a substition succeeded
#   - 'expr' is not a builtin, 'expr match' is not understood in, at least, FreeBSD
#     expr operations should have equivalent bash string manipulation expressions
#   - 'egrep' is deprecated in SUS v2, 'grep -E' replaces it [[x2]]
# * UNIX filter equivalencies
#   - cut -d: -f1 === awk -F: '{print $1}' === awk '{BEGIN FS=":"}; {print $1}'
#   - grep -v pattern === sed '/pattern/d'
# }}} # TO-DO

# {{{ # Constants

# Use configuration files to modify the behaviour of the
# script. Using them allows overriding some variables (see below)
# to your liking. Only lines with a variable assignment are evaluated,
# it should follow bash syntax, note though that ';' can't be used
# currently in the variable values; e.g.:
#
#	# Sample configuration for vcs
#	user=myname		# Sign all compositions as myname
#	bg_heading=gray	# Make the heading gray
#
# There is a total of four configuration files than are loaded if the exist:
# * /etc/vcs.conf: System wide conf, least precedence
# * ~/.vcs.conf: Per-user conf, second least precedence
# * ~/.vcs/vcs.conf: Per-user conf, alternate location for more complex configs
# * ./vcs.conf: Per-dir config, most precedence (deprecated)
#
# The variables that can be overriden are below the block of constants ahead.

# Default value for INTERVAL, setting interval to 0 also re-sets it to this value
declare -ri DEFAULT_INTERVAL=300

# see $DECODER
declare -ri DEC_MPLAYER=1 DEC_FFMPEG=3
# See $TIMECODE_FROM
declare -ri TC_INTERVAL=4 TC_NUMCAPS=8
# These can't be overriden, modify this line if you feel the need
declare -r PROGRAM_SIGNATURE="Video Contact Sheet *NIX ${VERSION}${SUBVERSION} <http://p.outlyer.net/vcs/>"
# Filename pattern for safe renaming (appending numbers until finding a name
#+not in use).
# Since 1.13 no longer configurable. Don't mess with it too much.
# By default "%b-%N.%e" where:
# %b is the basename (file name without extension)
# %N is the appended number
# %e is the extension
# Will first try %b.%e, then %b-1.%e, %b-2.%e and so on, i.e.
#+creates outputs like "output.avi-1.png"
declare -r SAFE_RENAME_PATTERN="%b-%N.%e"
# see $EXTENDED_FACTOR
declare -ri DEFAULT_EXT_FACTOR=4
# see $VERBOSITY
declare -ri V_ALL=5 V_NONE=-1 V_ERROR=1 V_WARN=2 V_INFO=3
# Indexes in $VID
declare -ri W=0 H=1 FPS=2 LEN=3 VCODEC=4 ACODEC=5 VDEC=6 CHANS=7 ASPECT=8 VCNAME=9 ACNAME=10
# Exit codes, same numbers as /usr/include/sysexits.h
declare -r EX_OK=0   EX_USAGE=64  EX_UNAVAILABLE=69  \
           EX_NOINPUT=66   EX_SOFTWARE=70   EX_CANTCREAT=73 \
           EX_INTERRUPTED=79 # This one is not on sysexits.h
# The context allows the creator to identify which contact sheet it is creating
# (CTX_*) HL: Highlight (-l), STD: Normal, EXT: Extended (-e)
declare -ri CTX_HL=1 CTX_STD=2 CTX_EXT=3

# Used for feedback
declare -r NL=$'\012' # Newline
#declare -r TAB=$'\011' # Tab

# New in 1.13
# Set to 1 to disable blank frame evasion
declare -i DISABLE_EVASION=0
# Threshold to consider a frame blank (see capture_and_evade)
declare -i BLANK_THRESHOLD=10
# Offsets to try when trying to avoid blank frames
# See capture() and capture_and_evade()
declare -a EVASION_ALTERNATIVES=( -5 +5 -10 +10 -30 +30 )

# Save the terminal settings to later restore them (in exithdlr)
declare -r STTY=$(stty -g)

# }}} # End of constants

# {{{ # Override-able variables
# GETOPT must be correctly set or the script will fail.
# It can be set in the configuration files if it isn't in the path or
# the first getopt in the path isn't the right version.
# A check will be made and a warning with details shown if required.
declare GETOPT=getopt
# Set to 1 to print function calls
declare -i DEBUG=0
# Text before the user name in the signature
declare SIGNATURE="Preview created by"
# By default sign as the system's username (see -u, -U)
declare USERNAME=$(id -un)
# Which of the two methods should be used to guess the number of thumbnails
declare -i TIMECODE_FROM=$TC_INTERVAL
# New in 1.13. Replaces the old 'decoder' symbolic option.
# The value is *not* the name of the executable, but a supported capturer,
#+right now 'ffmpeg' or 'mplayer'.
# When none is defined, the first available element in CAPTURERS is used.
declare CAPTURER=
# Options used in imagemagick, these options set the final aspect
# of the contact sheet
declare FORMAT=png     # ImageMagick decides the type from the extension
declare -i QUALITY=92  # Output image quality (only affects the final
                              # image and obviously only in lossy formats)
# Colours, see convert -list color to get the list
declare BG_HEADING='#afcd7a'    # Background for meta info (size, codec...)
declare BG_SIGN=SlateGray #'#a2a9af'       # Background for signature
declare BG_TITLE=White          # Background for the title (see -T)
declare BG_CONTACT=White        # Background for the captures
declare BG_TSTAMPS='#000000aa'  # Background for the timestamps box
declare FG_HEADING=Black        # Font colour for meta info box
declare FG_SIGN=Black           # Font colour for signature
declare FG_TSTAMPS=White        # Font colour for timestamps
declare FG_TITLE=Black          # Font colour for the title
# Fonts, use identify -list font to get the list, up to IM 6.3.5-7 was '-list type' [[IM1]]
# If a font is not available IM will pick a sane default. In theory it will be silent
# although in practice it prints an error
declare FONT_TSTAMPS=DejaVu-Sans-Book  # Used for timestamps over the thumbnails
declare FONT_HEADING=DejaVu-Sans-Book  # Used for the meta info heading
declare FONT_SIGN=$FONT_HEADING # Used for the signature box
declare FONT_TITLE=$FONT_HEADING # Used for the title (see -T)
# Font sizes, in points
declare -i PTS_TSTAMPS=14          # Used for the timestamps
declare -i PTS_META=14             # Used for the meta info heading
declare -i PTS_SIGN=10             # Used for the signature
declare -i PTS_TITLE=33            # Used for the title (see -T)
# See -E / $END_OFFSET
declare -r DEFAULT_END_OFFSET="5.5%"
# Controls how many extra captures will be created in the extended mode
# (see -e), 0 is the same as disabling the extended mode
# This number is multiplied by the total number of captures to get
# the number of extra captures. So, e.g. -n2 -e2 leads to 4 extra captures.
declare EXTENDED_FACTOR=0
# Verbosity level so far from the command line can only be muted (see -q)
# it can be overridden, though
declare -i VERBOSITY=$V_INFO
# Set to 1 to disable colours in console output
declare -i SIMPLE_FEEDBACK=0
# See coherence_check for more details
declare -i DISABLE_SHADOWS=0
declare -i DISABLE_TIMESTAMPS=0

# This font is used to display international names (i.e. CJK names) correctly
# Help from users who actually need this would be appreciated :)
# This variable is filled either automatically through the set_extended_font()
#+function (and option -Ij) or manually (with option -Ij=MyFontName)
# The automatic picks a semi-random one from the fonts believed to support CJK/Cyrillic
#+characters.
declare NONLATIN_FONT= # Filename or font name as known to ImageMagick (identify -list font)
# Introduced in 1.12.2:
# When true (1) uses $NONLATIN_FONT to print the filename, otherwise the same
#+font as the heading is used.
# See -I and --nonlatin
declare -i NONLATIN_FILENAMES=0
# Output of capturing programs is redirected here
declare STDOUT=/dev/null STDERR=/dev/null

# Override-able since 1.11:
# Height of the thumbnails, by default use same as input
declare HEIGHT='100%'
declare INTERVAL=$DEFAULT_INTERVAL	# Interval of captures (~length/$NUMCAPS)
declare -i NUMCAPS=16				# Number of captures (~length/$INTERVAL)
# This is the padding added to each capture.
# Beware when changing this since extended set's alignment might break.
# When shadows are enabled this is ignored since they already add padding.
# Starting with Bash 5 uppercase $COLUMNS can't be safely set in the script.
declare -i PADDING=2
declare -i NUM_COLUMNS=2				# Number of output columns
# This amount of time is *not* captured from the end of the video
declare END_OFFSET=$DEFAULT_END_OFFSET
# When set to 1 the signature won't contain the "Preview created by..." line
declare -i ANONYMOUS_MODE=0

# Profile(s) to load by default
declare PROFILES=

# }}} # End of override-able variables

# {{{ # Variables

# Options and other internal usage variables, no need to mess with this!
declare TITLE=""
declare FROMTIME=0          # Starting second (see -f)
declare TOTIME=-1           # Ending second (see -t)
declare -a INITIAL_STAMPS   # Manually added stamps (see -S)
declare -i MANUAL_MODE=0    # if 1, only command line timestamps will be used
declare ASPECT_RATIO=0      # If 0 no transformations done (see -a)
                            # If -1 try to guess (see -A)

declare -a TEMPSTUFF        # Temporary files
declare -a TIMECODES        # Timestamps of the video captures
declare -a HLTIMECODES      # Timestamps of the highlights (see -l)

declare VCSTEMPDIR=         # Temporary directory, all temporary files go there

# Identification output from ffmpeg and mplayer for the current video
declare FFMPEG_CACHE=
declare MPLAYER_CACHE=
# This holds the parsed identification values, see also the Indexes in VID
# (defined in the constants block)
declare -a VID=( )

# These variables will hold the output of tput, used
# to colourise feedback
declare PREFIX_ERR= PREFIX_INF= PREFIX_WARN= PREFIX_DBG= SUFFIX_FBACK=

# Workarounds:
# Argument order in FFmpeg is important -ss before or after -i will make
# the capture work or not depending on the file. See -Wo.
# TODO: [x1].
# Admittedly the workaraound is abit obscure: those variables will be added to
# the ffmpeg arguments, before and after -i, replacing spaces by the timestamp.
# e.g.: for second 50 '-ss ' will become '-ss 50' while '' will stay empty
# By default -ss goes before -i.
declare wa_ss_af="" wa_ss_be="-ss "

# Transformations/filters
# Operations are decomposed into independent optional steps, this allows
# to add some intermediate steps (e.g. polaroid/photo mode's frames)
# Filters in this context are functions.
# There're two kinds of filters and a delegate:
#  * individual filters are run over each vidcap
#  * global filters are run over all vidcaps at once (currently deprecated)
#  * The contact sheet creator delegates on some function to create the actual
#    contact sheet
#
# Individual filters take the form:
#  filt_name( vidcapfile, timestamp in seconds.milliseconds, width, height, [context, [index]] )
# They must set the variable $RESULT with parameters to add to 'convert', a single
#  call to convert will be issued for each capture like:
#  $ convert vidcap.png $RESULT [...] vidcap.png
# They're executed in order by filter_vidcap()
declare -a FILTERS_IND=( 'filt_resize' 'filt_apply_stamp' 'filt_softshadow' )
# Deprecated: Global filters take the form
#  filtall_name( vidcapfile1, vidcapfile2, ... )
# They're executed in order by filter_all_vidcaps
declare -a FILTERS_CS
# The contact sheet creators take the form
#  csheet_name( number of columns, context, width, height, vidcapfile1,
#               vidcapfile2, ... ) : outputfile
# Context is one of the CTX_* constants (see below)
# The width and height are those of an individual capture
# It is executed by create_contact_sheet()
declare CSHEET_DELEGATE=csheet_montage

# Holds a list of captured frames (to avoid recapturing)
# Format <timestamp>:<filename>[NL]<timestamp>:<filename>...
declare CAPTURES=

# Gravity of the timestamp
declare GRAV_TIMESTAMP=SouthEast

# Sets which function is used to obtain random numbers valid values are
# bashrand and filerand.
# Setting it manually will break it, calling with -R changes this to filerand.
# See rand() for an explanation
declare RANDFUNCTION=bashrand

# Which file are we working on (i.e. how many times has process() been called)
declare -i FILEIDX=0

# Names for output files, each index is a file name, an empty index will use
# the input file and append an extension to it
declare -a OUTPUT_FILES=( )

# Which of the two vidcappers should be used (see -F, -M)
#+mplayer seems to fail for mpeg or WMV9 files, at least on my system
#+also, ffmpeg allows better seeking: ffmpeg allows exact second.fraction
#+seeking while mplayer apparently only seeks to nearest keyframe
# Starting with 1.13 this value can no longer be overridden directly,
#+setting 'decoder' actually changes CAPTURER. DECODER is still used
#+internally.
declare -i DECODER=$DEC_FFMPEG

# Mplayer and FFmpeg binaries. Will be detected.
# Don't set manually, if you need to override set the path temporarily, e.g.:
# $ env PATH=/whatever:$PATH vcs ...
# or use the undocumented (and unchecked!) appropriate option:
# $ vcs --undocumented set_ffmpeg=/mypath/ffmpeg
declare MPLAYER_BIN=
declare FFMPEG_BIN=

# When set to 1 the reported length by mplayer and ffmpeg won't be trusted
# and will trigger some custom tests.
# Enabled automatically on problematic files
declare -i QUIRKS=0
# If the reported lengths differ by at least this much QUIRKS will be enabled
declare QUIRKS_LEN_THRESHOLD=0.2
# When trying to determine the correct length, file will be probed each...:
declare QUIRKS_LEN_STEP=0.5 # ~ 10 frames @ 20fps
# Maximum number of seconds to "rewind" from reported length (after this
# vcs surrenders but processing continues with a rewinded length)
declare QUIRKS_MAX_REWIND=20

# Set when the console output will be in color. It doesn't control color!
declare HAS_COLORS=

declare -i multiple_input_files=0

# Internal counts, used only to adjust messages
declare -i INTERNAL_WS_C=0 # -Ws count
declare -i INTERNAL_WP_C=0 # -Wp count
declare -i INTERNAL_MAXREWIND_REACHED=0 # More -Ws in the command-line won't help
# Loaded profiles.
# Not an array to ease seeking, each name is followed by an space:
#  Format: "profile1[SP]profile2[SP]"...
declare INTERNAL_L_PROFILES=

declare -r UNDFLAG_DISPLAY_COMMAND=eog  # Command to run with -Z display

# Stores the names of variables overridden from the command-line,
#+see cmdline_override() and "--override"
declare CMDLINE_OVERRIDES=""

# Implicit error handling (see die()), obviously inspired by C's errno
# and PHP's die(). Functions adapted to use them allow uses like:
#  some_function arg || die
# which will exit with the appropriate exit code and print the error message
# (Introduced in 1.12, still being retrofitted)
declare -i ERROR_CODE=0 # Exit code associated with the last error
declare ERROR_MSG=      # Error message associated to the last error

# Used to buffer feedback (see buffered())
declare BUFFER=

# This is only used to exit when -DD is used
declare -i DEBUGGED=0 # It will be 1 after using -DD

# See post_getopt_hooks()
# Format: Priority:Command[:Arguments] (lower priority run sooner)
declare -a POST_GETOPT_HOOKS=( )

declare -i DVD_MODE=0 DVD_TITLE=
declare -a DVD_TITLES=( ) # Titles for each input DVD, filled by --dvd-title
declare DVD_MOUNTP= # Mountpoint for DVD, detected & reset for each DVD
declare DVD_VTS=    # VTS, detected & reset for each DVD

# New in 1.13: Modularisation of video decoders and identifiers, to ease additions
# There's two types of video tools supported: capturers and identifiers
# A capturer is used to extract video frames
# An identifier is used to extract video information
# This abstraction provides an interface to allow easy addition of tools and
#+to handle missing tools with more ease than before. Each tool has a set of
#+associated functions, some of them optional that provide the same interface.
# Capturer functions:
#   <name>_capture(in, ts, out): Capture the frame from 'in' at 'ts' to 'out'
#   <name>_dvd_capture(in, ts, out) [optional]: Same for DVDs
# Identifier functions:
#   <name>_identify(f): Extract information from 'f', fill <NAME>_ID with it
#        also fills RESULT with the same values
#   <name>_probe(file, ts): Try reaching 'ts' (test for video length)

# Supported capturers. In order of preference.
# An associated <name>_capturer must be defined
CAPTURERS=( ffmpeg mplayer )
# Supported identifiers. In order of preference
# An associated <name>_identify must be defined
# 'classic' is a combination of ffmpeg and mplayer
IDENTIFIERS=( classic ffmpeg mplayer )
# Will be filled with the elements from CAPTURERS found on the system
# Lookup is done with <name>_check_avail, an associated <NAME>_BIN is to be
# defined there, i.e. mplayer_test_avail sets MPLAYER_BIN
CAPTURERS_AVAIL=( )
# Like CAPTURERS_AVAIL, for IDENTIFIERS
IDENTIFIERS_AVAIL=( )
# Same for IDENTIFIERS
IDENTIFIER=''
# If 1, the selected CAPTURER understands the use of milliseconds
CAPTURER_HAS_MS=0

# This variable is used in functions to avoid running them in a subshell, i.e.
# instead of
#   ret=$(myfunc)
# such functions are used as
#   myfunc
#   ret=$RESULT
# This way 'myfunc' has access to all variables and can modify them.
# Every function that modifies RESULT should overwrite its value.
RESULT=''
# Set by init_filt_film:
FILMSTRIP= # Filename of the sprocket-holes strip image
FILMSTRIP_HOLE_HEIGHT= # Height of an individual hole

# Set by -Z trace=<FILTER>, where <FILTER> is regex to reduce the trace
# verbosity. Only function names that match it will be printed.
# 'grep -p' will be used to match
INTERNAL_TRACE_FILTER=
INTERNAL_NO_TRACE=0 # When 1, tracing is disabled (used by -DD)

# }}} # Variables

# {{{ # Configuration handling

# New override system: This variable maps configuration variables to actual
#+variables used in the script. Each item in the array follows the syntax:
# <cfg variable>:<variable>:<flags>:[type constraints] Where:
#+ cfg variable: is the name of the configuration file variable
#+ variable: is the name of the actual variable. If empty or '=', it will be
#+           the same as cfg variable.
#+ flags can currently be:
#+  "deprecated=new name": Will print a deprecation warning and suggest to use
#+                         "new name" instead
#+  "striked": Variable is marked for removal, will print a warning about it
#+             directing anyone needing it to contact me. Only used for variables
#+             believed to be no longer needed
#+  "gone":    Variable removed in the current version
#+  "alias": Marks an alias, duplicate name intended to stay
#+  "meta":  Special variable that will modify other variables (e.g. font_all
#+           modifies all font_ variables.
#+  "=": ignore
#+ type constraints: a character indicating accepted values:
#     n  -> Number (Natural, positive Integer or zero)
#     p  -> Number, not zero
#     t  -> Timestamp
#     b  -> Bool
#     h  -> Positive, non-zero, number or percentage
#     f  -> Float or fraction
#     D  -> only $DEC_* constants
#     T  -> only $TC_* constants
#     V  -> only $V_* constants
#     I  -> interval or percentage
#     x  -> Special, variable with a set of possible values
# Note during the switch to the new system most variables will remain unchanged
# Also, the new system is case insensitive to variable names
declare -ra OVERRIDE_MAP=(
	"USER:USERNAME::"
	"EXTENDED_FACTOR:=:=:f"
	"STDOUT::"
	"STDERR::"
	"DEBUG:=:=:b"
	"INTERVAL:=:=:t"
	"NUMCAPS:=:=:p"
	"CAPTURES:NUMCAPS:alias:n" # Alias
	"GETOPT::" # Note it makes no sense as command-line override
	"NUM_COLUMNS:=:=:p"
	"COLS:COLUMNS:alias:p" # Traditional name
	"COLUMNS:NUM_COLUMNS:alias:p" # Up to 1.13.3

	"DISABLE_SHADOWS:=:=:b"
	"DISABLE_TIMESTAMPS:=:=:b"

	"BG_HEADING::"
	"BG_SIGN::"
	"BG_TITLE::"
	"BG_CONTACT::"
	"BG_TSTAMPS::"
	"FG_HEADING::"
	"FG_SIGN::"
	"FG_TSTAMPS::"
	"FG_TITLE::"
	"FONT_HEADING::"
	"FONT_SIGN::"
	"FONT_TSTAMPS::"
	"FONT_TITLE::"
	"FONT_ALL:=:meta" # see parse_override
	"BG_ALL:=:meta"
	"FG_ALL:=:meta"
	"PTS_TSTAMPS::"
	"PTS_META::"
	"PTS_SIGN::"
	"PTS_TITLE::"
	# Aliases for cosmetic stuff
	"BG_HEADER:BG_HEADING:alias"
	"BG_SIGNATURE:BG_SIGN:alias"
	"BG_FOOTER:BG_SIGN:alias"
	"BG_SHEET:BG_CONTACT:alias"
	"FG_HEADER:FG_HEADING:alias"
	"FG_SIGNATURE:FG_SIGN:alias"
	"FG_FOOTER:FG_SIGN:alias"
	"FONT_HEADER:FONT_HEADING:alias"
	"FONT_META:FONT_HEADING:alias"
	"FONT_SIGNATURE:FONT_SIGN:alias"
	"FONT_FOOTER:FONT_SIGN:alias"
	"PTS_HEADING:PTS_META:alias"
	"PTS_HEADER:PTS_META:alias"
	"PTS_SIGNATURE:PTS_SIGN:alias"
	"PTS_FOOTER:PTS_SIGN:alias"

	"SIGNATURE:=:"
	"USER_SIGNATURE:SIGNATURE:deprecated=SIGNATURE" # Deprecated since 1.12

	"QUALITY:=:=:n"
	"OUTPUT_QUALITY:QUALITY:deprecated=QUALITY:n" # Deprecated since 1.12

	# TODO: These variables are evaluated to constants, would be better to
	#       use some symbolic system (e.g. decoder=f instead of decoder=$DEC_FFMPEG)
	"DECODER:=:meta:D" # To be deprecated
	#"CAPTURE_MODE:TIMECODE_FROM:alias:T"
	"TIMECODE_FROM:=:=:T"
	"VERBOSITY:=:=:V"
	"SIMPLE_FEEDBACK:=:=:b"
	"CAPTURER:=:=:x" # Setting this modifies DECODER and CAPTURER_HAS_MS, from pick_tools()

	"HEIGHT:=:=:h"
	"PADDING:=:=:n"
	"NONLATIN_FONT::"
	"NONLATIN_FILENAMES:=:=:b"

	"ANONYMOUS:ANONYMOUS_MODE:=:b"

	"FORMAT::"

	"END_OFFSET:=:=:I" # New, used to have a two-variables assignment before USR_*

	"PROFILES:=:meta:P" # New in 1.13

	# TODO TBA:
	#"noboldfeedback::" # Colour but not bold

	# Deprecations, all these since 1.12
	"OUTPUT_FORMAT:FORMAT:deprecated=FORMAT"
	"PLAIN_MESSAGES:SIMPLE_FEEDBACK:deprecated=SIMPLE_FEEDBACK:b"
	"TH_HEIGHT:HEIGHT:deprecated=HEIGHT:h"
	"HPAD:PADDING:deprecated=PADDING:n"
	"FONT_MINCHO:NONLATIN_FONT:deprecated=NONLATIN_FONT"
	# Gone. Since 1.12
	"MIN_LENGTH_FOR_END_OFFSET::gone:"
	# Gone. Since 1.13
	"SHOEHORNED::gone"
	"SAFE_RENAME_PATTERN::gone"
	"DEFAULT_END_OFFSET::gone:"
)

# Load a configuration file
# File *MUST* exist
# Configuration files are a series of variable=value assignment; they'll be
#+evaluated directly so they can refer to other variables (with their value at
#+the point of the assignment).
# Quotes shouldn't be used (they'll be kept)
# Since 1.12 comments can be placed in-line (i.e. after an assignment),
# Literal '#' can be written as '$#'
# ';' can be used to mark an end of line, anything after it will be ignored
#+(making it equivalent to '#'), there's no way to include a literal ';'
# load_config_file($1 = file, [$2 = type (description) = 'Settings'])
load_config_file() {
	trace $@
	local cfgfile=$1
	local desc=$2
	[[ $desc ]] || desc='Settings'

	local por= # Parsed override
	local varname= tmp= flag= bashcode= feedback= ov=
	while read line ; do # auto variable $line
		[[ ! $line =~ ^[[:space:]]*# ]] || continue # Don't feed comments
		parse_override "$line"
		por=$RESULT
		if [[ $por ]]; then
			varname=${por/% *} # Everything up to the first space...
			tmp=${por#* } # Rest of string
			flag=${tmp/% *}
			if [[ $flag == '=' ]]; then
				# No need to override...
				feedback="$varname(=)"
			else
				feedback=$varname
			fi
			ov="$ov, $feedback"
		fi
	done <$cfgfile
	[[ -z $ov ]] || inf "$desc from $cfgfile:$NL ${ov:2}"
	# No loaded overrides but errors/warnings to print, do print the file name
	if [[ ( -z $ov ) && $BUFFER ]]; then
		inf "In $cfgfile:"
	fi
	flush_buffered ' '
}

# Loads the configuration files if present
# load_config()
load_config() {
	local -a CONFIGS=( /etc/vcs.conf ~/.vcs.conf ~/.vcs/vcs.conf ./vcs.conf )

	for cfgfile in "${CONFIGS[@]}" ;do
		[[ -f $cfgfile ]] || continue
		load_config_file "$cfgfile"
	done
	if [[ -f "./vcs.conf" ]]; then
		warn "'./vcs.conf' won't be loaded automatically starting with vcs 1.14"
		warn "  use '-C :pwd' to manually load it, or convert it to a profile"
	fi
}

# Load a profile, if found; fail otherwise
# Profiles are just configuration files that can be loaded on demand (whereas
#+config files are always loaded) and be given a name.
# See load_config_file() for comments on the syntax
# Locations to be searched, in order:
#+  1) ~/.vcs/profiles/NAME.conf
#+  2) /usr/local/share/vcs/profiles/NAME.conf
#+  3) /usr/share/vcs/profiles/NAME.conf
#+i.e. files in ~/.vcs/ will prevent loading files named like them in /usr
# load_profile($1 = profile name)
load_profile() {
	trace $@
	local p=$1 prof=
	local -a PATHS=( ~/.vcs/profiles/ /usr/local/share/vcs/profiles/ /usr/share/vcs/profiles/ )

	if [[ ${p:0:1} == ':' ]]; then
		case $p in
		:list)
			echo "Builtin profiles:"
			echo ' * classic: Classic colour scheme from previous versions'
			echo ' * 1.0: Initial colour scheme from ancient versions'
			# No need to be efficient here...
			echo "Profiles located:"
			local path= profname=
			# 1) Find all profiles
			# 2) (sed) Extract profile file name
			# 3 & 4) (sort+uniq) Keep only first hits for each name (most precedence)
			# 5) (while) Process each name
			# 6) (for) Re-locate most precedent profile
			# 7) (echo x3) Print <name>[: description]
			# 8) (sed) Indent with ' * '
			find "${PATHS[@]}" -name '*.conf' 2>/dev/null \
				| sed -e 's#.*/\(.*\)\.conf#\1#' \
				| sort | uniq \
				| while read profname ; do
					for path in "${PATHS[@]}" ; do
						path=$path$profname.conf
						[[ -f $path ]] || continue
						echo -n "$profname"
						# [ ] here contains <space><tab>. Mawk doesn't understand
						# [[:space:]]
						echo -n $(awk 'sub(/#[ 	]*vcs:desc:[ 	]*/, ": ")' "$path")
						echo
						break
					done
				done \
				| sed 's/^/ * /'
			exit 0
			;;
		*)
			ERROR_MSG="Profiles starting with ':' are reserved.$NL"
			ERROR_MSG+=" Use ':list' to list available profiles."
			ERROR_CODE=$EX_USAGE
			return $ERROR_CODE
		esac
	fi

	for prof in "${PATHS[@]}" ; do
		prof="$prof$p.conf"
		[[ -f $prof ]] || continue
		INTERNAL_L_PROFILES+="$p "
		load_config_file "$prof" 'Profile'
		return 0
	done
	ERROR_MSG="Profile '$p' not found"
	ERROR_CODE=$EX_USAGE
	return $ERROR_CODE
}

# Check value for an overrideable variable against the allowed values
# check_constraint($1 = variable name, $2 = value [, $3 = public_name])
#  where public_name is the name to be used for error messages
check_constraint() {
	trace $@
	local n=$1 v=$2 p=$3
	# Get constraint...
	local needle=$n
	#   ... use the public name to search UNLESS it is a command-line option
	if [[ ( -n $p ) && ! ( $p =~ ^- ) ]]; then
		needle=$p
	fi
	local map=$(echo "${OVERRIDE_MAP[*]}" | stonl | egrep -i "^$needle:")
	[[ $map ]] || return 0
	local ct=$(cut -d':' -f4 <<<"$map")
	[[ $ct ]] || return 0
	local checkfn= domain=
	case $ct in
		n) checkfn=is_number ; domain=numbers ;;
		p) checkfn=is_positive ; domain='numbers greater than zero' ;;
		t) checkfn=is_interval ; domain=intervals ;;
		b) checkfn=is_bool ; domain='boolean values (0 or 1)' ;;
		h) checkfn=is_pos_or_percent ; domain='positive numbers or percentages' ;;
		f) checkfn=is_float_or_frac ; domain='positive numbers or fractions' ;;
		D) checkfn=is_decoder ; domain='$DEC_FFMPEG or $DEC_MPLAYER' ;;
		T) checkfn=is_tcfrom ; domain='$TC_INTERVAL or $TC_INTERVAL' ;;
		V) checkfn=is_vlevel ; domain='verbosity levels ($V_.*)' ;;
		I) checkfn=is_interv_or_percent ; domain='intervals or percentages' ;;
		P) checkfn=is_profile_list ; domain='comma-separated profile names' ;;
		x)
			case "$p" in
				capturer)
					checkfn=is_known_capturer
					domain='mplayer or ffmpeg'
				;;
			esac
	esac
	if [[ -n $checkfn ]] && ! $checkfn "$v" ; then
		[[ -n $p ]] || p=$n
		ERROR_MSG="Illegal value for '$p', only $domain are accepted"
		ERROR_CODE=$EX_USAGE
		return $ERROR_CODE
	fi
	return 0
}

# Parse an override and set its value.
# Input should be a var=value assignment. Also sets USR_<variable>.
# The global variable $RESULT is set with the format:
# <variable name> <flag> where
#  * variable name: is the name of the variable to be overridden
#  * flag: is a character indicating the status: "+" for a possible override,
#         "=" for an override that already has the same value
# Warnings and errors are buffered
# This function always returns true
# parse_override($1 = override assignment)
parse_override() {
	trace $@
	local o="$1"
	RESULT=''
	
	# bash 3.1 and 3.2 handle quoted eres differently, using a variable fixes this
	local ERE="^[[:space:]]*[[:alpha:]_][[:alnum:]_]*[[:space:]]*=.*"

	if [[ ! $o =~ $ERE ]] ; then
		return
	fi
	local varname=$(echo "${o/=*}" | sed 's/[[:space:]]//g') # Trim var name
	local lcvarname=$(echo "$varname" | tr A-Z a-z)
	local mapping=$(echo "${OVERRIDE_MAP[*]}" | stonl | egrep -i "^$lcvarname:")

	[[ $mapping ]] || return 0

	local varval=${o#*=} # No trimming here (yet)
	#  1) Trim from ; (if present) to finish
	#  2) Trim from # (comments) not "escaped" like '$#'
	#  3) Replace '$#' with '#'
	#  4) Trim whitespace on both ends
	varval=$(sed -e 's/;.*//' -e 's/\([^$]\)#.*/\1/g' -e 's/\$#/#/g' \
				-e 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$varval")
	# Is varval empty?
	[[ $varval ]] || return 0

	local mvar=$(cut -d':' -f1 <<<"$mapping")
	local ivar=$(cut -d':' -f2 <<<"$mapping")
	local flags=$(cut -d':' -f3 <<<"$mapping")
	local constraints=$(cut -d':' -f4 <<<"$mapping")
	{ [[ $ivar && ( $ivar != '=' ) ]] ; } || ivar="$mvar"

	# Evaluate setting names, unlike actual variables they are
	#+case-insensitive and can mapped to different names so
	#+special handling is required
	local token= tokenmap=
	for token in $(echo "$varval" | grep -o '\$[[:alnum:]_]*' | sed 's/^\$//') ; do
		# Locate the mapping
		tokenmap=$(echo "${OVERRIDE_MAP[*]}" | stonl | egrep -i "^$token") || true
		if [[ -z $tokenmap ]]; then
			# No mapping, leave intact
			continue
		fi
		tokenmap=$(echo "$tokenmap" | cut -d':' -f2)
		if [[ -z $tokenmap ]]; then
			# No need to map, but change to uppercase for it to eval correctly
			tokenmap=$(tr a-z A-Z <<<"$token")
		fi
		# Replace all occurences of $token with its mapping
		varval=$(echo "$varval" | sed 's/\$'$token'/$'$tokenmap'/g')
	done

	# Note using "\$(echo $varval)" would allow a more flexible syntax but
	#+enforce special handling of escaping, which with the currently available
	#+settings is not worth the effort
	# Resolve symbolic variables to check their actual value
	eval varval="\"$varval\"" 2>/dev/null || { # Hide eval's errors
		buffered error "Syntax error: '$o'"
		return 0
	}

	[[ $varval ]] || return 0 # If empty value, ignore it

	local evcode=''
	if [[ $flags && ( $flags != '=' ) && ( $flags != 'alias' ) ]]; then
		local ERE='^deprecated='
		if [[ $flags =~ $ERE ]]; then
			local new=$(echo "$flags" | sed 's/^deprecated=//' | tr A-Z a-z)
			buffered warn "Setting '$varname' will be removed in the future,$NL please use '$new' instead."
		else
			case "$flags" in
				gone)
					buffered error "Setting '$varname' has been removed."
					return 0
					;;
				striked)
					buffered error "Setting '$varname' is scheduled to be removed in the next release."
					buffered error " Please contact the author if you absolutely need it."
					;;
				meta)
					if [[ -n $constraints ]] ; then
						if ! check_constraint $ivar "$varval" $varname ; then
							buffered error "$ERROR_MSG"
							return 0
						fi
					fi
					apply_meta_override "$varname" "$varval"
					RESULT="$varname +"
					return 0;
					;;
				*) return 0 ;;
			esac
		fi
	fi

	[[ -z $constraints ]] || check_constraint $ivar "$varval" $varname || {
		buffered error "$ERROR_MSG"
		return 0
	}

	eval local curvarval='$'"$ivar" retflag='+'
	if [[ $constraints == 't' ]]; then
		varval=$(get_interval "$varval")
	fi
	# Escape single quotes, since it will be single-quoted:
	varval=${varval//\'/\'\\\'\'} # <<'>> => <<'\''>>
	evcode="USR_$ivar='$varval'"
	if [[ $curvarval == "$varval" ]]; then
		retflag='='
	else
		evcode="$ivar='$varval'; $evcode"
	fi
	eval "$evcode"

	# varname, as found in the config file
	RESULT="$varname $retflag"
}

# Handle meta configuration variables, variables that, when set, modify the
# value of (various) others
# apply_meta_override($1 = actual variable name, $2 = value)
apply_meta_override() {
	trace $@
	case "$(tolower "$1")" in
		font_all)
			buffered inf "font_all => font_heading, font_sign, font_title, font_tstamps"
			parse_override "FONT_HEADING=$2"
			parse_override "FONT_SIGN=$2"
			parse_override "FONT_TITLE=$2"
			parse_override "FONT_TSTAMPS=$2"
		;;
		fg_all)
			buffered inf "fg_all => fg_heading, fg_sign, fg_title, fg_tstamps"
			parse_override "FG_HEADING=$2"
			parse_override "FG_SIGN=$2"
			parse_override "FG_TSTAMPS=$2"
			parse_override "FG_TITLE=$2"
		;;
		bg_all)
			buffered inf "bg_all => bg_heading, bg_contact, bg_sign, bg_title, bg_tstamps"
			parse_override "BG_HEADING=$2"
			parse_override "BG_CONTACT=$2"
			parse_override "BG_SIGN=$2"
			parse_override "BG_TITLE=$2"
			parse_override "BG_TSTAMPS=$2"
		;;
		profiles) # profiles=[,]prof1[,prof2,...], no spaces
			local profiles=${2//,/ } # === sed 's/,/ /g'
			local ERE='^[[:space:]]*$'
			if [[ $profiles =~ $ERE ]]; then
				return 0
			fi
			local prof=
			for prof in ${2//,/ } ; do # ${2//,/ } = sed 's/,/ /g'
				grep -q -v "$prof " <<<"$INTERNAL_L_PROFILES" || continue
				load_profile $prof || die
			done
		;;
		decoder)
			buffered inf "decoder => capturer"
			if [[ $2 -eq $DEC_FFMPEG ]]; then
				parse_override 'CAPTURER=ffmpeg'
			elif [[ $2 -eq $DEC_MPLAYER ]]; then
				parse_override 'CAPTURER=mplayer'
			else
				assert false
			fi
		;;
	esac
}

# Do an override from the command line
# cmdline_override($1 = override assignment)
#+e.g. cmdline_override 'verbosity=$V_ALL'
cmdline_override() {
	trace $@
	parse_override "$1"
	local r=$RESULT
	[[ $r ]] || return 0
	local varname=${r/% *} # See load_config()
	local tmp=${r#* }
	local flag=${tmp/% *}

	if [[ $flag == '=' ]]; then
		varname="$varname(=)"
	fi

	CMDLINE_OVERRIDES="$CMDLINE_OVERRIDES, $varname"
}

# Call any pending commands required by the command-line arguments
# This is used to defer some calls and to flush buffers
post_getopt_hooks() {
	local cback= EX=0
	local funcs=$(echo "${POST_GETOPT_HOOKS[*]}" | stonl | sort -n | uniq |\
			cut -d':' -f2- )
	for cback in $funcs ; do
		local fn=${cback/:*}
		local arg=${cback/*:}
		[[ $arg != $cback ]] || arg=''
		$fn $arg
	done
}

# Print the list of command-line overrides
cmdline_overrides_flush() {
	trace $@
	if [[ $CMDLINE_OVERRIDES ]]; then
		inf "Overridden settings from command line:$NL ${CMDLINE_OVERRIDES:2}"
	fi
	if [[ $BUFFER ]]; then
		[[ $CMDLINE_OVERRIDES ]] || warn "In command-line overrides:"
		flush_buffered ' '
	fi
}

# }}} # Configuration handling

# {{{ # Convenience functions

#### {{{{ # Type checkers: Return true if input is of a certain type
####                       All take exactly one argument and print nothing

## Natural number
is_number() {
	# With '[[...]]', strings '-eq'uals 0, test if it's actually 0
	#+or otherwise a valid number. Must return 1 on error.
	[[ ( $1 == '0' ) || ( $1 -gt 0 ) ]] 2>/dev/null || return 1
}
## Number > 0
is_positive() { is_number "$1" && [[ $1 -gt 0 ]]; }
## Bool (0 or 1)
is_bool() { [[ ($1 == '0') || ($1 == '1') ]] 2>/dev/null ; }
## Float (XX.YY; XX.; ;.YY) (.24=0.24)
## XXX: 1.12.3:      '^([0-9]+\.?([0-9])?+|(\.[0-9]+))$'
is_float() { local P='^([0-9]+\.?[0-9]*|\.[0-9]+)$' ; [[ $1 =~ $P ]] ; }
## Percentage (xx% or xx.yy%)
## XXX: 1.12.3:      '^([0-9]+\.?([0-9])?+|(\.[0-9]+))%$'
is_percentage() {
	local P='^([0-9]+\.?[0-9]*|\.[0-9]+)%$'
	[[ $1 =~ $P ]]
}
## Interval
is_interval() {
	local i=$(get_interval "$1" || true)
	[[ $i ]] && fptest $i -gt 0
}
## Interval or percentage
is_interv_or_percent() {
	is_percentage "$1" || is_interval "$1"
}
## Positive or percentage
is_pos_or_percent() {
	is_number "$1" && [[ $1 -gt 0 ]] || is_percentage "$1"
}
## Float (>=0) or fraction
is_float_or_frac() {
	{ is_fraction "$1" || is_float "$1" ; } && fptest "$1" -ge 0
}
## Fraction, strictly (X/Y, but no X; Y!=0)
is_fraction() {
	local P='^[0-9]+/[0-9]+$'
	[[ $1 =~ $P ]] && {
		local d=${1#*/} # .../X
		[[ $d -ne 0 ]]
	}
}
## Decoder ($DEC_* constants)
is_decoder() { [[ $1 == $DEC_FFMPEG || $1 == $DEC_MPLAYER ]]; }
is_known_capturer() {
	[[ ( $1 == 'mplayer' ) || ( $1 == 'ffmpeg' ) ]]
}
## Time calculation source ($TC_* constants)
is_tcfrom() { [[ $1 == $TC_INTERVAL || $1 == $TC_NUMCAPS ]]; }
## Verbosity level ($V_* constants)
is_vlevel() {
	is_number "$1" && \
		[[ ($1 -eq $V_ALL) || ($1 -eq $V_NONE) || ($1 -eq $V_ERROR) || \
			($1 -eq $V_WARN) || ($1 -eq $V_INFO) ]]
}
## List of profiles (comma-separated)
is_profile_list() {
	ERE='^([[:alnum:]]*,?)*$'
	[[ ( -z "$*" ) || ( "$*" =~ $ERE ) ]]
}

#### }}}} # End of type checkers

# Makes a string lowercase
# tolower($1 = string)
tolower() { tr '[:upper:]' '[:lower:]' <<<"$1" ; }

# Rounded product
# multiplies parameters and prints the result, rounded to the closest int
# parameters can be separated by commas or spaces
# e.g.: rmultiply 4/3,576 OR 4/3 576 = 4/3 * 576 = 768
# rmultiply($1 = operator1, [$2 = operator2, ...])
# rmultiply($1 = "operator1,operator2,...")
rmultiply() {
	awkex "int(${*//[ ,]/ * }+0.5)" # ' ' = ',' => '*'
}

# Like rmultiply() but always rounded upwards
ceilmultiply() {
	# TODO: breaks with $@. Why?
	awkex "int(${*//[ ,]/ * }+0.99999)"  # ' ' = ',' => '*'
}

# Basic mathematic stuff
# min($1 = operand1, $2 = operand2)
# max($1 = operand1, $2 = operand2)
# abs($1 = number)
min() { awk "BEGIN { if (($1) < ($2)) print ($1) ; else print ($2) }" ; }
max() { awk "BEGIN { if (($1) > ($2)) print ($1) ; else print ($2) }" ; }
abs() { awk "BEGIN { if (($1) < (0)) print (($1) * -1) ; else print ($1) }" ; }

# Rounds a number ($1) to a multiple of ($2)
# rtomult($1 = number, $2 = divisor)
rtomult() {
	local n=$1 d=$2
	local r=$(( $n % $d ))
	if [[ $r -ne 0 ]]; then
		(( n += ( d - r ) , 1 ))
	fi
	echo $n
}

# Numeric test eqivalent for floating point
# fptest($1 = op1, $2 = operator, $3 = op2)
# special operator: '~' uses fsimeq()
fptest() {
	local op=
 	# Empty operands
	if [[ ( -z $1 ) || ( -z $3 ) ]]; then
		assert "[[ \"'$1'\" && \"'$3'\" ]] && false"
	fi
	case $2 in
		-gt) op='>' ;;
		-lt) op='<' ;;
		-ge) op='>=' ;;
		-le) op='<=' ;;
		-eq) op='==' ;;
		-ne) op='!=' ;;
		~)
			fsimeq "$1" "$3"
			return $?
			;;
		*) assert "[[ \"'$1' '$2' '$3'\" ]] && false" && return $EX_SOFTWARE
	esac
	awk "BEGIN { if ($1 $op $3) exit 0 ; else exit 1 }"
}

# floating point fuzzy equality, like fptest
# fsimeq($1 = op1, $2 = op2)
fsimeq() {
	awk "BEGIN { if (($1 - $2)^2 < 0.000000001) exit 0 ; else exit 1 }"
}

# Keep a number of decimals *rounded*
# keepdecimals($1 = num, $2 = number of decimals)
keepdecimals() {
	local N=$1 D=$2
	awk "BEGIN { printf \"%.${D}f\", (($N)+0) }"
}

# Keep a number of decimals, last decimal rounded to lower
keepdecimals_lower() {
	local ERE='\.'
	[[ $1 =~ $ERE ]] || { echo "$1" ; return ; }
	local D=${1/#*.} # Decimals only
	echo ${1/%.*}.${D:0:$2} # Integer part + . + Number of decimals
}

# Evaluate in AWK. Intended for arithmetic operations.
#+Keep decimals. I.e. 5 = 5.000000...
# awkexf($1 = expression)
awkexf() {
	# By default awk prints in compact form (scientific notation and/or up to 6 digits/decimals),
	# printf is used to avoid this, TODO: Is there any direct way?
	# .%20f is clearly overkill but matches the old code (default bc -l)
	# TODO: gawk and mawk differ in how to handle stuff like div by zero:
	#       gawk errors, mawk prints inf. Should somehow handle inf and nan
	awk "BEGIN { printf \"%.20f\", ($1)+0 }"
}

# Evaluate in AWK. Intended for arithmetic operations.
#+Use default output. I.e. 5 = 5
# awkex($1 = expression)
awkex() {
	awk "BEGIN { print ($1)+0 }"
}

# converts spaces to newlines in a x-platform way [[FNL]]
# stonl([$1 = string])
stonl() {
	if [[ $1 ]]; then
		awk '{gsub(" ", "\n");print}' <<<"$1" | egrep -v '^$'
	else
		awk '{gsub(" ", "\n");print}' | egrep -v '^$'
	fi
}

# Converts newlines to spaces portably
# nltos([$1 = string])
nltos() {
	if [[ $1 ]]; then
		awk '{printf "%s ",$0}' <<<"$1" | sed 's/ *//'
	else
		awk '{printf "%s ",$0}' | sed 's/ *//'
	fi
}

# bash version of ord() [[ORD]]
# prints the ASCII value of a character
ord() {
	printf '%d' "'$1"
}

# Get file extension
filext() {
	grep -q '\.' <<<"$1" || return 0
	awk -F. '{print $NF}' <<<"$1"
}

# Checks if a 'command' is defined either as an available binary, a function
#+or an alias
# is_defined($1 = command)
is_defined() {
	type "$@" >/dev/null 2>&1
}

# Checks if a command is an available binary in the path.
# is_executable($1 = command)
is_executable() {
	type -pf "$@" >/dev/null 2>&1
}

# Checks if a variable has been defined (even to empty values).
# isset($1 = variable name)
isset() {
	[[ -n ${!1+x} ]]
}

# Wrapper around $RANDOM, not called directly, wrapped again in rand().
# See rand() for an explanation.
bashrand() {
	echo $RANDOM
}

# Prepares for "filerand()" calls
# File descriptor 7 is used to keep a file open, from which data is read
# and then transformed into a number.
# init_filerand($1 = filename)
init_filerand() { # [[FD1]], [[FD2]]
	test -r "$1"
	exec 7<"$1"
	# closed in exithdlr
}

# Produce a (not-really-)random number from a file, not called directly wrapped
# in rand()
# Note that once the file end is reached, the random values will always
# be the same (hash_string result for an empty string)
filerand() {
	local b=
	# "read 5 bytes from file descriptor 7 and put them in $b"
	read -n5 -u7 b
	hash_string "$b"
}

# Produce a random number
# $RANDFUNCTION defines wich one to use (bashrand or filerand).
# Since functions using random values are most often run in subshells
# setting $RANDOM to a given seed has not the desired effect.
# filerand() is used to that effect; it keeps a file open from which bytes
# are read and not-so-random values generated; since file descriptors are
# inherited, subshells will "advance" the random sequence.
# Argument -R enables the filerand() function
rand() {
	$RANDFUNCTION
}

# produces a numeric value from a string
hash_string() {
	local HASH_LIMIT=65536
	local v=$1
	local -i hv=15031
	local c=
	if [[ $v ]]; then
		for i in $(seqr 0 ${#v} ); do
			c=$( ord ${v:$i:1} )
			hv=$(( ( ( $hv << 1 ) + $c ) % $HASH_LIMIT ))
		done
	fi
	echo $hv
}

# Applies the Pythagorean Theorem
# pyth_th($1 = cathetus1, $2 = cathetus2)
pyth_th() {
	awkexf "sqrt($1 ^ 2 + $2 ^ 2)"
}

# Get a percentage
# percent($1 = value, $2 = percentage)
percent() {
	local pc=${2/%%/} # BASH %% == RE %$
	awkexf "($1 * $pc) / 100"
}

# Rounded percentage
# rpercent($1 = value, $2 = percentage)
rpercent() {
	local pc=${2/%%/}
	awkex "int( ($1 * $pc) / 100 + 0.5 )"
}

# Prints the width correspoding to the input height and the variable
# aspect ratio
# compute_width($1 = height) (=AR*height) (rounded)
compute_width() {
	rmultiply $ASPECT_RATIO,$1
}

# Parse an interval and print the corresponding value in seconds
# returns something not 0 if the interval is not recognized.
#
# The current code is a tad permissive, it allows e.g. things like
# 10m1h (equivalent to 1h10m)
# 1m1m  (equivalent to 2m)
# I don't see reason to make it more anal, though.
# get_interval($1 = interval)
get_interval() {
	trace $@
	# eval it even if it's numeric to strip leading zeroes. Note the quoting
	if is_number "$1" ; then awkexf "\"$1\"" ; return 0 ; fi

	local s=$(tolower "$1") r

	# Only allowed characters
	local ERE='^[0-9smhSMH.]+$'
	[[ $s =~ $ERE ]] || return $EX_USAGE

	# Two consecutive dots are no longer accepted
	# ([.] required for bash 3.1 + bash 3.2 compat)
	[[ ! $s =~ [.][.] ]] || return $EX_USAGE

	# Newer(-er) parsing code: replaces units by a product
	# and feeds the resulting string to awk for evaluation
	# Note leading zeroes will lead awk to believe they are octal numbers
	#  as a quick and dirty fix I'm just wrapping them in quotes, forcing awk
	#  to re-evaluate them, which appears to be enough to make them decimal.
	#  This is the only place where leading zeroes have no meaning.
	# sed expressions:
	#   1: add spaces after h,m,s and before '.'
	#   2: add a space at the start (every number will now have a space in front)
	#   3: quote numbers preceded by a space
	#   4: replace h with a product by 3600 and an addition
	#   5: replace m with a product by 60 and an addition
	#   6: replace s with an addition
	#   7: add a '+' between consecutive quoted values
	#   8: remove last empty addition
	local exp=$(echo "$s" | sed \
							-e 's/\([hms]\)/\1 /g' -e 's/\./ ./g' \
							-e 's/^/ /' \
							-e 's/ \([0-9.][0-9.]*\)/ "\1"/g' \
							-e 's/h/ * 3600 + /g' \
							-e 's/m/ * 60 + /g' \
							-e 's/s/ + /g' \
							-e 's/"[[:space:]]*"/" + "/g' \
							-e 's/+ *$//' \
							)
	r=$(awkexf "$exp" 2>/dev/null)

	# Negative and empty intervals
	assert "[[ '$r' ]]"
	assert "fptest $r -gt 0"

	echo $r
}

# Pads a string with zeroes on the left until it is at least
# the indicated length
# pad($1 = minimum length, $2 = string)
pad() {
	# Must allow non-numbers
	local l; (( l = $1 - ${#2} , 1 ))
	[[ $l -le 0 ]] || printf "%0${l}d" '0'
	echo $2
}

# Get Image Width
# imw($1 = file)
imw() {
	identify -format '%w' "$1"
}

# Get Image Height
# imh($1 = file)
imh() {
	identify -format '%h' "$1"
}

# Get the line height used for a certain font and size
# line_height($1 = font, $2 = size)
line_height() {
	# Create a small image to see how tall are characters. In my tests, no
	#+matter which character is used it's always the same height.
	convert -font "$1" -pointsize "$2" \
		label:'F' png:- | identify -format '%h' -
}

# Prints a number of seconds in a more human readable form
# e.g.: 3600 becomes 1:00:00
# pretty_stamp($1 = seconds)
pretty_stamp() {
	assert "is_float '$1'"
	assert 'isset CAPTURER_HAS_MS'
	# Fully implemented in AWK to discard bc.

	# As a bonus now it's much faster and compact
	awk "BEGIN {
		t=$1 ; NOTMS=!$CAPTURER_HAS_MS;
		MS=(t - int(t));
		h=int(t / 3600);
		t=(t % 3600);
		m=int(t / 60);
		t=(t % 60);
		s=t
		if (h != 0) h=h\":\" ; else h=\"\"
		if (NOTMS!=1) ms=sprintf(\".%02d\", int(MS*100+0.5));
		printf \"%s%02d:%02d%s\", h, m, s, ms
	}"
	# Note the rounding applied to $MS, it is required to match the precission passed on
	# to ffmpeg
}

# Prints a given size in human friendly form
get_pretty_size() {
	local bytes=$1
	local size=

	# Sizes are always rounded up (hence the addition 0.999999 to the fractionary part)
	# gawk understands the ** operator, but mawk does not, using precomputed
	#  values for the sake of compatibility
	declare -ri GBS=$(( 1024**3 ))
	declare -ri MBS=$(( 1024**2 ))
	if [[ $bytes -gt $GBS ]]; then
		local gibs_int=$(( $bytes / $GBS ))
		local gibs_frac=$(awkex "int($bytes%$GBS*100/$GBS + 0.999999)" )
		size="$(printf '%d.%02d' $gibs_int $gibs_frac) GiB"
	elif [[ $bytes -gt $MBS ]]; then
		local mibs_int=$(( $bytes / $MBS ))
		local mibs_frac=$(awkex "int($bytes%$MBS*100/$MBS + 0.999999)")
		size="$(printf '%d.%02d' $mibs_int $mibs_frac) MiB"
	elif [[ $bytes -gt 1024 ]]; then
		local kibs_int=$(( $bytes / 1024 ))
		local kibs_frac=$(awkex "int($bytes%1024*100/1024 + 0.999999)")
		size="$(printf '%d.%02d' $kibs_int $kibs_frac) KiB"
	else
		size="${bytes} B"
	fi

	echo $size
}

# Prints the size of a file in a human friendly form
# The units are in the IEC/IEEE/binary format (e.g. MiB -for mebibytes-
# instead of MB -for megabytes-)
# get_pretty_file_size($1 = file)
get_pretty_file_size() {
	local f="$1"
	local bytes=$(get_file_size "$f")

	get_pretty_size "$bytes"
}

# mv quiet
# Move a file, be quiet about errors.
# Ownership preservation is a common error on vfs, for example
mvq() {
	mv -- "$@" 2>/dev/null
}

# Rename a file, if the target exists, try with appending numbers to the name
# And print the output name to stdout
# See $SAFE_RENAME_PATTERN
# safe_rename($1 = original file, $2 = target file)
# XXX: Note it fails if target has no extension
safe_rename() {
	trace $@
	local from="$1"
	local to="$2"

	# Output extension
	local ext=$(filext "$to")
	# Output filename without extension
	local b=${to%.$ext}

	local n=1
	while [[ -f $to ]]; do # Only executes if $2 exists
		# Bash 2 and Bash 3 behave differently with substring replacement (${//}) and '%'
		# Sed is a safer bet
		to=$(sed -e "s#%b#$b#g" -e "s#%N#$n#g" -e "s#%e#$ext#g" <<<"$SAFE_RENAME_PATTERN")

		(( n++ ));
	done
	assert "[[ -n '${to//\'/\'\\\'\'}' ]]" # [[ -n '$to' ]] + escape single quotes

	mvq "$from" "$to"
	echo "$to"
}

# Gets the file size in bytes
# get_file_size($1 = filename)
# du can provide bytes or kilobytes depending on the version used. The difference
# can be notorius...
# Neither busybox's nor BSD's du allow --bytes.
# Note that using "ls -H" is not an option for portability reasons either.
get_file_size() {
	# First, try the extended du arguments:
	local bytes
	bytes=$(du -L --bytes "$1" 2>/dev/null) || {
		echo $(( 1024 * $(du -Lk "$1" | cut -f1) ))
		return
	}
	# Getting to here means the first du worked correctly
	cut -f1 <<<"$bytes"
}

# Du replacement. This differs from get_file_size in that it takes multiple arguments
dur() {
	for file in $@ ; do
		get_file_size "$file"
	done
}

# Gets the size of the dvd device, in DVD mode
get_dvd_size() {
	# FIXME: Case sensivity might break with iso9660
	if [[ -f "$DVD_MOUNTP/VIDEO_TS/VTS_${DVD_VTS}_1.VOB" ]]; then
		# Some VOBs available
		local vfiles="$DVD_MOUNTP/VIDEO_TS/VTS_${DVD_VTS}_*.VOB"
		# Print all sizes, each on a line, add '+' to the end of each line, add 0 to the end.
		local feed="$(dur "$DVD_MOUNTP/VIDEO_TS/VTS_${DVD_VTS}_"*".VOB" | cut -f1 | sed 's/$/ + /') 0"
		get_pretty_size $(awkex "$(nltos "$feed")")
	else
		echo "?"
	fi
}

is_linux() {
	uname -s | grep -iq '^Linux$'
}

# Get the mountpoint of a mounted image.
# This only works on Linux. *BSD normal users aren't able to use mdconfig -l
# Is there any better way?
# get_dvd_image_mountpoint($1 = image file)
get_dvd_image_mountpoint() {
	if is_linux ; then
		local lodev=$(/sbin/losetup -j "$1" | cut -d':' -f1 | head -1)
		mount | grep "^$lodev " | cut -d' ' -f3
	fi
}

# Tests the presence of all required programs
# test_programs()
test_programs() {
	local retval=0 last=0
	local nopng=0

	MPLAYER_BIN=$(type -pf mplayer) || true
	FFMPEG_BIN=$(type -pf ffmpeg)   || true
	check_avail_tools

	# awk is required by SUS/POSIX but just to be sure...
	for prog in convert montage identify mktemp grep egrep cut sed awk ; do
		if ! type -pf "$prog" ; then
			error "Required program $prog not found!"
			(( retval++ ,1 ))
		fi >/dev/null
	done
	# TODO: [[x2]]

	# Early exit
	[[ $retval -eq 0 ]] || return $EX_UNAVAILABLE

	# ImageMagick version. 6 is a must, I'm probably using some
	# features that require a higher minor version
	# Versions tested:
	# * Fedora 9: IM 6.4.0
	local ver
	ver=$(convert -version | sed -n -e '1s/.*ImageMagick \([0-9][^ ]*\) .*$/\1/p;q')
	if [[ $ver ]]; then
		local verx=${ver//-/.}.0 # Extra .0 in case rev doesn't exist
		local major=$(cut -d'.' -f1 <<<"$verx")
		local minor=$(cut -d'.' -f2 <<<"$verx")
		local micro=$(cut -d'.' -f3 <<<"$verx")
		local rev=$(cut -d'.' -f4 <<<"$verx")
		local serial=$(( $major * 100000 + $minor * 10000 + $micro * 100 + $rev))
		if [[ $serial -lt 630507 ]]; then
			error "ImageMagick 6.3.5-7 or higher is required. Found $ver." ;
			(( retval++ ,1 ))
		fi
	else
		error "Failed to check ImageMagick version."
		(( retval++ ,1 ))
	fi

	[[ $retval -eq 0 ]] || return $EX_UNAVAILABLE
}

# Test wether $GETOP is a compatible version; try to choose an alternate if
# possible
choose_getopt() {
	if ! type -pf "$GETOPT" ; then
		#  getopt not in path
		error "Required program getopt not found!"
		return $EX_UNAVAILABLE
	fi >/dev/null
	local goe= gor=0
	# Try getopt. If there's more than one in the path, try all of them
	for goe in $(type -paf $GETOPT) ; do
		"$goe" -T || gor=$?
		if [[ $gor -eq 4 ]]; then
			# Correct getopt found
			GETOPT="$goe"
			break;
		fi
	done >/dev/null
	if [[ $gor -ne 4 ]]; then
		error "No compatible version of getopt in path, can't continue."
		error " Enhanced getopt (i.e. GNU getopt) is required"
		return $EX_UNAVAILABLE
	fi
	return 0
}

# Remove any temporary files
# Does nothing if none has been created so far
# cleanup()
cleanup() {
	if [[ -z $TEMPSTUFF ]]; then return 0 ; fi
	inf "Cleaning up..."
	rm -rf "${TEMPSTUFF[@]}"
	unset VCSTEMPDIR
	unset TEMPSTUFF ; declare -a TEMPSTUFF
}

# Exit callback. This function is executed on exit (correct, failed or
# interrupted)
# exithdlr()
exithdlr() {
	# I don't think that's really required anyway
	if [[ $RANDFUNCTION == 'filerand' ]]; then
		7<&-	# Close FD 7
	fi
	cleanup
	# XXX: In one of my computers a terminal reset is required
	#tset
	stty "$STTY"
}

# Feedback handling, these functions are use to print messages respecting
# the verbosity level
# Optional color usage added from explanation found in
# <http://wooledge.org/mywiki/BashFaq>
#
# error($1 = text)
error() {
	if [[ $VERBOSITY -ge $V_ERROR ]]; then
		[[ $SIMPLE_FEEDBACK -eq 0 ]] && echo -n "$PREFIX_ERR"
		# sgr0 is always used, this way if
		# a) something prints inbetween messages it isn't affected
		# b) if SIMPLE_FEEDBACK is overridden colour stops after the override
		echo "$1$SUFFIX_FBACK"
	fi >&2
	# It is important to redirect both tput and echo to stderr. Otherwise
	# n=$(something) wouldn't be colourised
}
#
# Print a non-fatal error or warning
# warning($1 = text)
warn() {
	if [[ $VERBOSITY -ge $V_WARN ]]; then
		[[ $SIMPLE_FEEDBACK -eq 0 ]] && echo -n "$PREFIX_WARN"
		echo "$1$SUFFIX_FBACK"
	fi >&2
}
#
# Print an informational message
# inf($1 = text)
inf() {
	if [[ $VERBOSITY -ge $V_INFO ]]; then
		[[ $SIMPLE_FEEDBACK -eq 0 ]] &&  echo -n "$PREFIX_INF"
		echo "$1$SUFFIX_FBACK"
	fi >&2
}
#
# Print a debugging message
# notice($1 = text)
notice() {
	if [[ $VERBOSITY -gt $V_INFO ]]; then
		[[ $SIMPLE_FEEDBACK -eq 0 ]] && echo -n "$PREFIX_DBG"
		echo "$1$SUFFIX_FBACK"
	fi >&2
}

#
# Same as inf but with no colour ever.
# infplain($1 = text)
infplain() {
	if [[ $VERBOSITY -ge $V_INFO ]]; then
		echo "$1" >&2
	fi
}

#
# Buffering of feedback, usage:
#  buffered warn "my warning"
#  ...
#  flush_buffered
# buffered($1 = feedback function, $2 = arguments)
buffered() {
	local grab=$( $1 "$2" 2>&1 )
	BUFFER=$BUFFER$grab$NL
}

#
# Print buffered feedback to stderr
# flush_buffered([$1 = indentation])
flush_buffered() {
	[[ ${BUFFER[*]} ]] || return 0
	echo "$BUFFER" | sed -e '$d' -e "s/^/$1/g" >&2 # sed: delete last line, indent with $1
	BUFFER=''
}

#
# trace(... = function arguments)
trace() {
	[[ $DEBUG -eq 1 ]] || return 0
	[[ $INTERNAL_NO_TRACE -ne 1 ]] || return 0
	local func=$(caller 0 | cut -d' ' -f2) # caller: <LINE>< ><FUNCTION>< ><FILE>
	if [[ -n $INTERNAL_TRACE_FILTER ]]; then
		if ! grep -Pq "$INTERNAL_TRACE_FILTER" <<<"$func" ; then
			return 0
		fi
	fi
	notice "[TRACE]: $func ${*}"
}

#
# Print the call stack / execution frames
# callstack([$1 = first frame]=0)
callstack() {
	[[ $DEBUG -eq 1 ]] || return 0
	local frame=$1 c= fn=
	[[ -n $frame ]] || frame=0
	echo "Callstack:"
	while : ; do
		c=$(caller $frame) || break
		c=${c% *}
		fn=${c#* }
		# Only the last one, main, won't be a function
		if [[ $(type -t $fn) == 'function' ]]; then
			fn="${fn}()"
		fi
		echo "    ${fn}:${c% *}"
		(( ++frame ))
	done
}

# Print an error message and exit
# die([$1 = message [, $2 = exit_code]])
#  If no message is provided, use $ERROR_MSG
#  If no exit_code is provided, use $ERROR_CODE
die() {
	local m=$1 ec=$2
	[[ $ec ]] || ec=$ERROR_CODE
	[[ $ec ]] || ec=1
	[[ $m  ]] || m=$ERROR_MSG
	error "$m"
	exit $ec
}

#
# Tests if the filter chain contains the provided filter
# has_filter($1 = filtername)
has_filter() {
	local filter= ref=$1
	for filter in ${FILTERS_IND[@]} ; do
		[[ $filter == "$ref" ]] || continue
		return 0
	done
	return 1
}

#
# Enables prefixes in console output (instead of colour)
set_feedback_prefixes() {
	PREFIX_ERR='[E] '
	PREFIX_INF='[i] '
	PREFIX_WARN='[w] '
	PREFIX_DBG=''
	SUFFIX_FBACK=
}

#
# Initialises the variables affecting colourised feedback
init_feedback() {
	HAS_COLORS=

	# tput might be preferable (Linux: man console_codes), but it doesn't
	# work on FreeBSD to set colors

	# Is tput available?
	if type -pf tput >/dev/null ; then
		# First we must find the correct way to query color support.
		# There's basically two variants of tput:
		#   terminfo (Linux) and termcap (FreeBSD)
		# These is an issue for portability:
		# - On Linux 'tput colors' is used to query it
		# - On FreeBSD 'tput Co' is used to query it
		# - Linux's tput will fail if it's passed 'Co'
		# - FreeBSD's tput will interpret 'colors' as 'co' and print the number of columns
		local tputc="-1"
		if tput Co >/dev/null 2>&1 ; then
			tputc=$(tput Co) # termcap style
		else
			# Try to guess if it's parsing it as columns
			# The method here is to check against some known terminals
			# pilot: 39 columns mono, pc3: 80 columns, 8 colors
			if [[ 8 = "$(tput -T pc3 colors)" ]]; then
				# colors is interpreted literally
				tputc=$(tput colors)
			fi
		fi
		# Is it able to set colours?
		# Linux's tput can be passed arguments to retrieve the correct escape sequences
		# FreeBSD's tput can not
		if tput bold && [[ "-1" != "$tputc" ]] && tput setaf 0 && tput sgr0; then
			# Can configure completely through tput
			PREFIX_ERR=$(tput bold; tput setaf 1)
			PREFIX_WARN=$(tput bold; tput setaf 3)
			PREFIX_INF=$(tput bold; tput setaf 2)
			PREFIX_DBG=$(tput bold; tput setaf 4)
			SUFFIX_FBACK=$(tput sgr0)
			HAS_COLORS="yes"
		elif [[ "-1" != "$tputc" ]]; then
			# tput reports color support but it doesn't provide
			# the escape codes directly, will use hardcoded escape codes instead
			HAS_COLORS=
		else
			HAS_COLORS="no"
			set_feedback_prefixes
		fi >/dev/null
	fi

	if [[ -z $HAS_COLORS ]]; then
		# tput was not an option, let's try ANSI escape codes instead [[AEC]]
		# TODO: Detect support
		# Alternatively: $ perl -e 'print "\e[31m\e[1m"'
		# echo -e is not portable but echo $'' is bash-specific so it should be fine...
		# except when ANSI escape codes aren't supported of course
		PREFIX_ERR=$(echo $'\033[1m\033[31m')
		PREFIX_WARN=$(echo $'\033[1m\033[33m')
		PREFIX_INF=$(echo $'\033[1m\033[32m')
		PREFIX_DBG=$(echo $'\033[1m\033[34m')
		SUFFIX_FBACK=$(echo $'\033[0m')
		HAS_COLORS="yes"
	fi

	# Finally, if there's no colour support, use prefixes instead
	if [[ -z $HAS_COLORS ]]; then
		set_feedback_prefixes
	fi
}

#
# seq replacement
# seq is not always present, jot is an alternative on FreeBSD. Instead, this is
# a direct replacement
# Note pure bash is *slower* than the awk (or perl) version
# seqr($1 = from, $2 = to, $3 = increment)
seqr() {
	local from=$1 to=$2 inc=$3
	[[ $inc ]] || inc=1
	awk "BEGIN { for (i=$from;i<=$to;i+=$inc) print i }"
}

# assertion operator
# Note: Use single quotes for globals, no need to expand in release
# assert(... = code)
assert() {
	[[ $RELEASE -eq 0 ]] || {
		function assert { :; } # Redefine to avoid check
	}
	local c=$(caller 0) # <num> <func> <file>
	c=${c% *} # <num> <func>
	local LIN=${c% *} FN=${c#* }
	eval "$@" || {
		error "Internal error at $FN():$LIN: $@"
		local cal=$(caller 1)
		[[ $level ]] && error "  Stack trace:"
		local level=2
		error "$(callstack 1 | sed 's/^/    /')"
		exit $EX_SOFTWARE
	}
}

# Conditional assertion
# assert_if($1 = condition, $2 = assert if $1 true)
assert_if() {
	[[ $RELEASE -eq 1 ]] && return
	if eval "$1" ; then
		assert "$2"
	fi
}

# }}} # Convenience functions

# {{{ # Core functionality

# {{{{ # Mplayer support

# Check for mplayer
mplayer_test_avail() {
	MPLAYER_BIN=$(type -pf mplayer 2>/dev/null)
	[[ $MPLAYER_BIN ]] && {
		if ! "$MPLAYER_BIN" -vo help 2>&1 | grep -q 'png' ; then
			warn "MPlayer can't output to png, won't be able to use it."
			unset MPLAYER_BIN
			return $EX_UNAVAILABLE
		fi
	}
}

# Try to identify video properties using mplayer
# Fills $MPLAYER_CACHE with the relevant output and $MPLAYER_ID with
# the actual values. See identify_video()
# mplayer_identify($1 = file)
mplayer_identify() {
	trace $@
	assert '[[ $MPLAYER_BIN ]]'
	local f="$1"
	local mi=( )
	# Note to self: Don't change the -vc as it would affect $vdec
	if [[ $DVD_MODE -eq 0 ]]; then
		MPLAYER_CACHE=$("$MPLAYER_BIN" -benchmark -ao null -vo null -identify -frames 0 \
							-quiet "$f" 2>"$STDERR" | grep '^ID')
	else
		MPLAYER_CACHE=$("$MPLAYER_BIN" -benchmark -ao null -vo null -identify -frames 0 \
							-quiet -dvd-device "$f" dvd://$DVD_TITLE \
							2>"$STDERR" | grep '^ID')
	fi
	# Note the head -1!
	mi[$VCODEC]=$(grep ID_VIDEO_FORMAT <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2) # FourCC
	mi[$ACODEC]=$(grep ID_AUDIO_FORMAT <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2)
	mi[$VDEC]=$(grep ID_VIDEO_CODEC <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2) # Decoder (!= Codec)
	mi[$W]=$(grep ID_VIDEO_WIDTH <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2)
	mi[$H]=$(grep ID_VIDEO_HEIGHT <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2)
	mi[$FPS]=$(grep ID_VIDEO_FPS <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2)
	# For some reason my (one track) samples have two ..._NCH, first one 0
	#+Also multichannel is detected as 2 ch
	mi[$CHANS]=$(grep ID_AUDIO_NCH <<<"$MPLAYER_CACHE"| grep -v '=0' | cut -d'=' -f2|head -1)
	if [[ $DVD_MODE -eq 0 ]]; then
		# For DVDs it prints ID_DVD_TITLE_x_LENGTH and ID_LENGTH.
		#+Both appear valid.
		mi[$LEN]=$(grep ID_DVD_TITLE_${DVD_TITLE}_LENGTH <<<"$MPLAYER_CACHE"| cut -d'=' -f2)
		[[ ${mi[$LEN]} ]] || mi[$LEN]=$(grep ID_LENGTH <<<"$MPLAYER_CACHE"| head -1 | cut -d'=' -f2)
	else
		mi[$LEN]=$(grep ID_DVD_TITLE_${DVD_TITLE}_LENGTH <<<"$MPLAYER_CACHE"| head -1 | cut -d'=' -f2)
	fi
	# Voodoo :P Remove (one) trailing zero
	if [[ "${mi[$FPS]:$(( ${#mi[$FPS]} - 1 ))}" == '0' ]]; then
		mi[$FPS]="${mi[$FPS]:0:$(( ${#mi[$FPS]} - 1 ))}"
	fi
	mi[$ASPECT]=$(grep ID_VIDEO_ASPECT <<<"$MPLAYER_CACHE" | egrep -v '^0.0000$' | cut -d'=' -f2 | tail -1)
	# If none set, delete it
	[[ ${mi[$ASPECT]} ]] && fptest "${mi[$ASPECT]}" -eq 0.0 && mi[$ASPECT]=''
	mi[$VCNAME]=$(get_vcodec_name "${mi[$VCODEC]}")
	if [[ ( ${mi[$VDEC]} == 'ffodivx' ) && ( ${mi[$VCNAME]} != 'MPEG-4' ) ]]; then
		mi[$VCNAME]="${mi[$VCNAME]} (MPEG-4)"
	elif [[ ${mi[$VDEC]} == 'ffh264' ]]; then # At least two different fourccs use h264, maybe more
		mi[$VCNAME]="${mi[$VCNAME]} (h.264)"
	fi
	mi[$ACNAME]=$(get_acodec_name "${mi[$ACODEC]}")
	if [[ ${mi[$ACODEC]} == 'samr' ]] ; then
		local adec=$(grep ID_AUDIO_CODEC <<<"$MPLAYER_CACHE" | head -1 | cut -d'=' -f2)
		if [[ $adec == 'ffamrnb' ]]; then
			mi[$ACNAME]="AMR-NB";
		fi
	fi

	# Warn if a known pitfall is found
	# NOTE: These messages are supressed if called from classic_identify
	# See above for 1000 fps
	[[ ${mi[$FPS]} == '1000.00' ]] && \
		warn "Possible inaccuracy in FPS detection." && \
		warn "    Install both mplayer and ffmpeg for better detection."
	# Number of channels 0 happened for WMA in non-x86
	[[ ${mi[$CHANS]} == '0' ]] && \
		warn "Failed to detect number of audio channels." && \
		warn "    Install both mplayer and ffmpeg for better detection."

	# Array assignment
	MPLAYER_ID=("${mi[@]}")
	RESULT=("${mi[@]}")
}

# Capture a frame with mplayer
# mplayer_capture($1 = inputfile, $2 = timestamp, $3 = output[, $4 = extra options])
mplayer_capture() {
	trace $@
	# Note mplayer CAN'T set the output filename, newer mplayer can set output
	#+dir though.
	local f="$1"
	local ts=$2
	local cap=00000005.png o=$3

	# No point in passing ms to mplayer
	ts=$(cut -d'.' -f1 <<<"$ts")
	# Capture 5 frames and drop the first 4, fixes a weird bug/feature of mplayer ([M1])

	assert '[[ $DVD_MODE -ne 1 ]]'
	"$MPLAYER_BIN" -sws 9 -ao null -benchmark -vo "png:z=0" -quiet \
		   -frames 5 -ss "$ts" $4 "$f" >"$STDOUT" 2>"$STDERR"
	rm -f 0000000{1,2,3,4}.png # Remove the first four
	[[ ( -f $cap ) && ( '0' != "$(du "$cap" | cut -f1)" ) ]] && {
		[[ $cap == "$o" ]] || mvq "$cap" "$o"
	}
}

# Capture a frame with mplayer
# mplayer_dvd_capture($1 = inputfile, $2 = timestamp, $3 = output)
mplayer_dvd_capture() {
	trace $@
	# Note mplayer CAN'T set the output filename, newer mplayer can set output
	#+dir though.
	local f="$1"
	local cap=00000005.png o=$3
	local ts=$2

	# No point in passing ms to mplayer
	ts=$(cut -d'.' -f1 <<<"$ts")

	assert '[[ $DVD_MODE -eq 1 ]]'
	"$MPLAYER_BIN" -sws 9 -ao null -benchmark -vo "png:z=0" -quiet \
		   -frames 5 -ss "$ts" -dvd-device "$f" \
		   $4 "dvd://$DVD_TITLE" >"$STDOUT" 2>"$STDERR"
	rm -f 0000000{1,2,3,4}.png # Remove the first four
	[[ ( -f $cap ) && ( '0' != "$(du "$cap" | cut -f1)" ) ]] && {
		[[ $cap == "$o" ]] || mvq "$cap" "$o"
	}
}

mplayer_probe() {
	local r= f=00000005.png
	if [[ $DVD_MODE -eq 1 ]]; then
		mplayer_dvd_capture "$1" "$2" "$f" "-vf scale=96:96"
	else
		mplayer_capture "$1" "$2" "$f" "-vf scale=96:96"
	fi
	r=$?
	rm -f "$f" # Must be manually removed since this runs before process()
	return $r
}

# }}}} # Mplayer support

# {{{{ # FFmpeg support

# Check for ffmpeg
ffmpeg_test_avail() {
	FFMPEG_BIN=$(type -pf ffmpeg 2>/dev/null)
	# Test we can actually use FFmpeg
	[[ $FFMPEG_BIN ]] && {
		# Newer FF has -codecs, -formats, -protocols, older has only -formats
		#+png is a codec so it's on different lists on newer and older
		if ! "$FFMPEG_BIN" -formats 2>/dev/null | grep -q 'EV.* png' && \
			! "$FFMPEG_BIN" -codecs 2>/dev/null | grep -q 'EV.* png' ; then
			warn "FFmpeg can't output to png, won't be able to use it."
			unset FFMPEG_BIN
			return $EX_UNAVAILABLE
		fi
	}
}

# Try to identify video properties using ffmpeg
# Fills $FFMPEG_CACHE with the relevant output and $FFMPEG_ID with
# the actual values. See identify_video()
# mplayer_identify($1 = file)
ffmpeg_identify() {
	trace $@
	assert '[[ $FFMPEG_BIN ]]'
	local f="$1"
	# DVD Devices *MUST* be mounted for the identifying process to even start
	assert '[[ $DVD_MODE -eq 0 || $DVD_MOUNTP ]]'
	if [[ $DVD_MODE -eq 1 ]]; then
		local vfile="$DVD_MOUNTP/VIDEO_TS/VTS_${DVD_VTS}_0.VOB"
		if [[ ! -r $vfile ]]; then
			error "Failed to locate mounted DVD. Detection will be less accurate."
			return 0 # We can continue anyway
		fi
		f="$vfile"
	fi
	# XXX: FFmpeg detects mpeg1video in DVDs??

	local fi=( ) vs= as= obs= vsid=
	# FFmpeg is relatively new, introduced in 1.0.99 so it needs more testing
	FFMPEG_CACHE=$("$FFMPEG_BIN" -i "$f" -dframes 0 -vframes 0 /dev/null 2>&1 | egrep '(Stream|Duration:|^Seems)')
	# Only the first streams of each type are honored. FIXME: Add multi-audio support.
	vs=$(sed -n -e '/Stream/!d' -e '/Video:/!d' -e '/Video:/p;q' <<<"$FFMPEG_CACHE")
	as=$(sed -n -e '/Stream/!d' -e '/Audio:/!d' -e '/Audio:/p;q' <<<"$FFMPEG_CACHE")
	obs=$(grep Seems <<<"$FFMPEG_CACHE")
	# Stream #0.0: Video: mpeg4, yuv420p, 624x352 [PAR 1:1 DAR 39:22], 23.98 tbr, 23.98 tbn, 24k tbc
	# New and old versions of ffmpeg changed their output considerably, e.g.:
	# (same file, Robotica_720.wmv)
	# New output:
	#  Seems stream 1 codec frame rate differs from container frame rate: 1000.00 (1000/1) -> 23.98 (24000/1001)
	#  [...]
	#  Duration: 00:00:20.77, start: 3.000000, bitrate: 6250 kb/s
	#  Stream #0.0(eng): Audio: wmapro, 48000 Hz, 6 channels, s16, 384 kb/s
	#  Stream #0.1(eng): Video: wmv3, yuv420p, 1280x720, 6500 kb/s, 23.98 tbr, 1k tbn, 1k tbc
	# Old output:
	#  Duration: 00:00:20.7, start: 3.000000, bitrate: 6250 kb/s
	#  Stream #0.0: Audio: 0x0162, 48000 Hz, 5:1, 384 kb/s
    #  Stream #0.1: Video: wmv3, yuv420p, 1280x720, 24.00 fps(r)
	# TODO: tbr is rounded to two decimals but the actual ratio is printed:
	# 24000/1001 = 23.97602
	#   (older ffmpeg prints 24 fps, 24/1 so no luck here
	# **Also seen**: (note the 'tb(r)')
	# Stream #0.1: Video: wmv3, yuv420p, 1440x1080 [PAR 4:3 DAR 16:9], 8000 kb/s, 23.98 tb(r)
	# **Also seen**: (VOB, latest ffmpeg as of this writing):
	# Stream #0.0[0x1e0]: Video: mpeg2video, yuv420p, 720x576 [PAR 64:45 DAR 16:9], 9800 kb/s, 23.53 fps, 25 tbr, 90k tbn, 50 tbc
	# **Also seen**: (DVB TS to DX50 in MKV), note the DAR mess, the second one is the correct one
	# Stream #0.0: Video: mpeg4, yuv420p, 640x326 [PAR 1:1 DAR 320:163], PAR 231:193 DAR 73920:31459, 25 fps, 25 tbr, 1k tbn, 25 tbc
	vsid=$(sed -n -e 's/^.*#0\.\([0-9]\).*$/\1/p' <<<"$vs") # Video Stream ID
	fi[$VCODEC]=$(sed -n -e 's/^.*Video: \([^,]*\).*$/\1/p' <<<"$vs")
	# ffmpeg's codec might contain spaces in some cases, i.e. iv4 in mov (see mplayer's bestiary)
	#+unless this turns out to be common I won't be handling it specially
	# Note unidentified audio codecs will be printed in hexadecimal
	fi[$ACODEC]=$(sed -n -e 's/^.*Audio: \([^,]*\).*$/\1/p' <<<"$as")
	fi[$VDEC]=''
	# The comma is required for cases where the stream id is printed (in hex)
	fi[$W]=$(sed -n -e 's/^.*, \([0-9]*\)x[0-9].*$/\1/p' <<<"$vs")
	fi[$H]=$(sed -n -e 's/^.*, [0-9]*x\([0-9]*\).*$/\1/p' <<<"$vs")
	# Newer CHANS and some older...
	fi[$CHANS]=$(sed -n -e 's/.*\([0-9][0-9]*\) channels.*/\1/p' <<<"$as")
	# ...fallback for older
	if [[ -z ${fi[$CHANS]} ]]; then
		local chans=$(sed -n -e 's/.*Hz, \([^, ][^, ]*\).*$/\1/p' <<<"$as")
		case $chans in
			mono) fi[$CHANS]=1 ;;
			stereo) fi[$CHANS]=2 ;;
			5.1|5:1) fi[$CHANS]=6 ;; # *
			*) ;; # Other layouts use 'N channels'
			# 5.1 was in the previous version (can't remember if it was empirical).
		esac
	fi
	# Newer FPS...
	# tbr/tbn/tbc explanation: tb stands for time base
	#  n: AVStream, c: AVCodecContext, r: VideoStream (Guessed)
	# tbr is the best bet. Note it's common for WMVs to contains "1k tbn, 1k tbc"
	# tbr is rounded to two decimals, the values used to derived it might be
	# printed in a "Seems ..." line like the one in the example above so it
	# can be re-calculated.
	fi[$FPS]=$(egrep -o '[0-9]*\.?[0-9]*k? tb(r|\(r\))' <<<"$vs" | cut -d' ' -f1)
	# Let's convert e.g. 23.98 into 23.976...:
	if [[ ${fi[$FPS]} ]] && grep -q '\.' <<<"${fi[$FPS]}" ; then
		# Decimals, see if we got better values available
		local vsobs=$(grep "stream $vsid" <<<"$obs")
		# Observations regarding video stream found
		if [[ $vsobs ]] && grep -q " -> ${fi[$FPS]} (.*)" <<<"$vsobs" ; then
			# FPS candidate
			local newfps=$(egrep -o -- '-> [^ ]* \([0-9]*/[0-9]*' <<<"$vsobs" | cut -d'(' -f2)
			is_fraction $newfps && fi[$FPS]=$(keepdecimals "$newfps" 3)
		fi
	fi
	# ...fallback for older. The older version I tried seems to round further, i.e.
	# 23.976 became 24 so no fix for this one
	if [[ -z ${fi[$FPS]} ]]; then
		# No k suffix here, 1000 is 1000
		fi[$FPS]=$(sed 's/.*, \([0-9]*\.[0-9]*\) fps.*/\1/' <<<"$vs")
	fi
	# Be consistent with mplayer's output: at least two decimals
	[[ ${fi[$FPS]} ]] && {
		fi[$FPS]=$(keepdecimals "${fi[$FPS]}" 3)
		fi[$FPS]=${fi[$FPS]/%0} # Strip 0$
	}
	fi[$LEN]=$(sed -n -e '/Duration: /!d' \
						-e 's/.*Duration: \([^,][^,]*\).*/\1/p;q' <<<"$FFMPEG_CACHE")
	if [[ ${fi[$LEN]} == 'N/A' ]]; then # It might be unable to detect
		fi[$LEN]=""
	fi
	fi[$LEN]=$( get_interval $(echo "${fi[$LEN]}" | sed -e 's/:/h/' -e 's/:/m/') )
	# Aspect ratio in FFmpeg is only provided in newer ffmpeg
	# It might be calculated for files without one (which is ok anyway)
	# Must only match the last DAR (see the double DAR example above)
	fi[$ASPECT]=$(sed -n -e '/DAR [0-9]/!d' \
							-e 's#.*DAR \([0-9]*\):\([0-9]*\).*#\1/\2#p;q' <<<"$FFMPEG_CACHE")
	# Due to calling ffmpeg on a single VOB when in DVD Device mode, the length will be partial
	[[ $DVD_MODE -eq 0 ]] || fi[$LEN]=''
	fi[$VCNAME]=$(get_vcodec_name $(translate_ffmpeg_vcodec_id "${fi[$VCODEC]}"))
	fi[$ACNAME]=$(get_acodec_name $(translate_ffmpeg_acodec_id "${fi[$ACODEC]}"))
	if [[ "${fi[$VCODEC]}" == 'h264' ]]; then
		fi[$VCNAME]="${fi[$VCNAME]} (h.264)"
	fi

	FFMPEG_ID=("${fi[@]}")
	RESULT=("${fi[@]}")
}

ffmpeg_probe() {
	local tfile=$(new_temp_file '-probe.png')
	ffmpeg_capture "$1" "$2" "$tfile" "-s 96x96"
}

# Capture a frame with ffmpeg
# ffmpeg_capture($1 = inputfile, $2 = timestamp, $3 = output[, $4 = extra opts])
ffmpeg_capture() {
	trace $@
	local f=$1
	local ts=$2
	local o=$3
	
	# XXX: It would be nice to show a message if it takes too long
	# See wa_ss_* declarations at the start of the file for details
	"$FFMPEG_BIN" -y ${wa_ss_be/ / $ts} -i "$f" ${wa_ss_af/ / $ts} -an \
		  -dframes 1 -vframes 1 -vcodec png \
		  -f rawvideo $4 "$o" >"$STDOUT" 2>"$STDERR"
	[[ ( -f $o ) && ( '0' != "$(du "$o" | cut -f1)" ) ]]
}

# }}}} # FFmpeg support

# {{{{ # Classic identification (combined mplayer & ffmpeg)

# Test availability
classic_test_avail() {
	mplayer_test_avail && ffmpeg_test_avail
}

# }}}} # Classic identification

# Sets the tool to use as a capturer
# Possible tool names: ffmpeg, mplayer
# set_capturer($1 = tool, [$2 = user picked]=1)
set_capturer() {
	trace $@
	local up=$2
	[[ -n $up ]] || up=1

	if [[ $up -eq 1 ]] && ! grep -q "$1" <<<"${CAPTURERS_AVAIL[*]}" ; then
		error "Tried to set '$1' as capturer, but not available"
		return 1
	fi

	if [[ $1 = mplayer ]]; then
		DECODER=$DEC_MPLAYER
		CAPTURER=mplayer
		CAPTURER_HAS_MS=0
	elif [[ $1 = ffmpeg ]]; then
		DECODER=$DEC_FFMPEG
		CAPTURER=ffmpeg
		CAPTURER_HAS_MS=1
	else
		assert false
	fi
	if [[ $up -eq 1 ]]; then
		USR_DECODER=$DECODER
		USR_CAPTURER=$CAPTURER
	fi
}

# Creates a new temporary directory
# create_temp_dir()
create_temp_dir() {
	trace $@

	[[ -z $VCSTEMPDIR ]] || return 0

	# Try to use /dev/shm if available, this provided a very small
	# benefit on my system but me of help for huge files. Or maybe won't.
	# Passing a full path template is more x-platform than using
	# -t / -p
	if [[ ( -d /dev/shm ) && ( -w /dev/shm ) ]]; then
		VCSTEMPDIR=$(mktemp -d /dev/shm/vcs.XXXXXX)
	else
		[[ $TMPDIR ]] || TMPDIR="/tmp"
		VCSTEMPDIR=$(env TMPDIR="$TMPDIR" mktemp -d "$TMPDIR/vcs.XXXXXX")
	fi
	if [[ ! -d $VCSTEMPDIR ]]; then
		error "Error creating temporary directory"
		return $EX_CANTCREAT
	fi
	TEMPSTUFF=( "${TEMPSTUFF[@]}" "$VCSTEMPDIR" )
}

# Resolve path. Realpath is not always available and readlink [[LC]] behaves differently in
# GNU and BSD.
# XXX: Has AWK or bash something similar? This is the only place requiring perl!
# realpathr($1 = path) -> canonical path
realpathr() {
	perl -e "use Cwd qw(realpath);print realpath('$1')"
}

# Create a new temporal file and print its filename
# new_temp_file($1 = suffix)
new_temp_file() {
	trace $@
	local r=$(env TMPDIR="$VCSTEMPDIR" mktemp "$VCSTEMPDIR/vcs-XXXXXX")
	if [[ ! -f $r ]]; then
		error "Failed to create temporary file"
		return $EX_CANTCREAT
	fi
	r=$(safe_rename "$r" "$r$1") || {
		error "Failed to create temporary file"
		return $EX_CANTCREAT
	}
	TEMPSTUFF=( "${TEMPSTUFF[@]}" "$r" )
	echo "$r"
}

# Randomises the colours and fonts. The result won't be of much use
# in most cases but it might be a good way to discover some colour/font
# or colour combination you like.
# randomize_look()
randomize_look() {
	trace $@
	local mode=f lineno

	if [[ $mode == 'f' ]]; then # Random mode
		# There're 5 rows of extra info printed
		local ncolours=$(( $(convert -list color | wc -l) - 5 ))
		randcolour() {
		lineno=$(( 5 + ( $(rand) % $ncolours ) ))
		convert -list color | sed -n "${lineno}{p;q;}" | cut -d' ' -f1 # [[R1#11]]
		}
	else # Pseudo-random mode, WIP!
		randccomp() {
			# colours are in the 0..65535 range, while RANDOM in 0..32767
			echo $(( $(rand) + $(rand) + ($(rand) % 1) ))
		}
		randcolour() {
			echo "rgb($(randccomp),$(randccomp),$(randccomp))"
		}
	fi

	# Older IM output was pretty different. Since this is a mode used for testing
	# I don't believe it's worth the effort to get it always right
	
	# This used to be -list type. Was this an older IM version or a bug in vcs?
	local nfonts=$(convert -list font | grep '^\s*Font:' | wc -l)
	randfont() {
		lineno=$(( $(rand) % $nfonts ))
		convert -list font | sed -n -e '/Font: ./!d' -e 's/^.*Font: //' -e "${lineno}{p;q}"
	}

	BG_HEADING=$(randcolour)
	BG_SIGN=$(randcolour)
	BG_TITLE=$(randcolour)
	BG_CONTACT=$(randcolour)
	FG_HEADING=$(randcolour)
	FG_SIGN=$(randcolour)
	FG_TSTAMPS=$(randcolour)
	FG_TITLE=$(randcolour)
	FONT_TSTAMPS=$(randfont)
	FONT_HEADING=$(randfont)
	FONT_SIGN=$(randfont)
	FONT_TITLE=$(randfont)
	inf "Randomisation result:
 Chosen backgrounds:
   '$BG_HEADING' for the heading
   '$BG_SIGN' for the signature
   '$BG_TITLE' for the title
   '$BG_CONTACT' for the contact sheet
 Chosen font colours:
   '$FG_HEADING' for the heading
   '$FG_SIGN' for the signature
   '$FG_TITLE' for the title
   '$FG_TSTAMPS' for the timestamps,
 Chosen fonts:
   '$FONT_HEADING' for the heading
   '$FONT_SIGN' for the signature
   '$FONT_TITLE' for the title
   '$FONT_TSTAMPS' for the timestamps"

   unset -f randcolour randfound randccomp
}

# Add to $TIMECODES the timecodes at which a capture should be taken
# from the current video
# compute_timecodes($1 = timecode_from, $2 = interval, $3 = numcaps)
compute_timecodes() {
	trace $@

	local st=0 end=${VID[$LEN]} tcfrom=$1 tcint=$2 tcnumcaps=$3 eo=0
	local eff_eo= # Effective end_offset (for percentages)

	# globals: $FROMTIME, $TOTIME, $TIMECODE_FROM, $TIMECODES, $END_OFFSET
	if fptest $st -lt $FROMTIME ; then
		st=$FROMTIME
	fi
	if fptest $TOTIME -gt 0 && fptest $end -gt $TOTIME ; then
		end=$TOTIME
	fi
	if is_percentage $END_OFFSET ; then
		eff_eo=$(percent $end $END_OFFSET)
	else
		eff_eo=$(get_interval "$END_OFFSET")
	fi
	if fptest $TOTIME -le 0 ; then # If no totime is set, use END_OFFSET
		eo=$eff_eo

		local runlen=$(awkexf "$end - $st")

		if fptest "($end-$eo-$st)" -le 0 ; then
			if fptest "$eo" -gt 0 && [[ -z $USR_END_OFFSET ]] ; then
				warn "Default end offset was too high for the video, ignoring it."
				eo=0
			else
				error "End offset too high, use e.g. '-E0'."
				return $EX_UNAVAILABLE
			fi
		fi
	fi

	local inc=
	if [[ $tcfrom -eq $TC_INTERVAL ]]; then
		inc=$tcint
	elif [[ $tcfrom -eq $TC_NUMCAPS ]]; then
		# Numcaps mandates: timecodes are obtained dividing the length
		# by the number of captures
		if [[ $tcnumcaps -eq 1 ]]; then # Special case, just one capture, center it
			inc=$(awkexf "(($end-$st)/2 + 1)")
		else
			inc=$(awkexf "(($end-$eo-$st)/$tcnumcaps)")
		fi
	else
		error "Internal error"
		return $EX_SOFTWARE
	fi
	if [[ $CAPTURER_HAS_MS -eq 0 ]]; then
		inc=$(keepdecimals_lower $inc 0)
	else
		# Keep three decimals, round to lower to avoid exceeding the video length
		inc=$(keepdecimals_lower $inc 3)
	fi

	if fptest $inc -gt ${VID[$LEN]}; then
		error "Capture interval is longer than video length, skipping '$f'"
		return $EX_USAGE
	fi
	if fptest $inc -eq 0; then
		error "Capture interval is too low, skipping '$f'"
		return $EX_UNAVAILABLE
	fi

	local stamp=$st
	local -a LTC
	local bound=$(awkexf "$end - $eo")
	local last=
	while fptest $stamp -le "$bound"; do
		# Due to rounding (i.e. with mplayer), the loop might need an extra run
		# to reach the end of the video.
		# Ensure it doesn't if the user requested a specific number of captures
		if [[ ( $tcfrom -eq $TC_NUMCAPS ) && ( ${#LTC[@]} -gt $tcnumcaps ) ]]; then
			break
		fi
		assert fptest $stamp -ge 0
		LTC=( "${LTC[@]}" "$stamp" )
		last=$stamp
		stamp=$(keepdecimals_lower $(awkexf "$stamp + $inc") 3)
	done
	local lower_bound=$(awkexf "$st + $inc")
	inf "Capturing in range [$(pretty_stamp $lower_bound)-$(pretty_stamp $last)]. Total length: $(pretty_stamp ${VID[$LEN]})"
	unset LTC[0] # Discard initial cap (=$st)
	TIMECODES=( "${TIMECODES[@]}" "${LTC[@]}" )
}

# Tries to guess an aspect ratio comparing width and height to some
# known values (e.g. VCD resolution turns into 4/3)
# guess_aspect($1 = width, $2 = height)
guess_aspect() {
	trace $@
	local w=$1 h=$2 ar

	case "$w" in
		352)
			if [[ ( $h -eq 288 ) || ( $h -eq 240 ) ]]; then
				# Ambiguous, could perfectly be 16/9
				# VCD / DVD @ VCD Res. / Half-D1 / CVD
				ar=4/3
			elif [[ ( $h -eq 576 ) || ( $h -eq 480 ) ]]; then
				# Ambiguous, could perfectly be 16/9
				# Half-D1 / CVD
				ar=4/3
			fi
			;;
		704|720)
			if [[ ( $h -eq 576 ) || ( $h -eq 480 ) ]]; then # DVD / DVB
				# Ambiguous, could perfectly be 16/9
				ar=4/3
			fi
			;;
		480)
			if [[ ( $h -eq 576 ) || ( $h -eq 480 ) ]]; then # SVCD
				ar=4/3
			fi
			;;
	esac

	if [[ -z $ar ]]; then
		if [[ ( $h -eq 720 ) || ( $h -eq 1080 ) ]]; then # HD
			ar=16/9
		fi
	fi

	if [[ -z $ar ]]; then
		warn "Couldn't guess aspect ratio."
		ar="$w/$h" # Don't calculate it yet
	fi

	echo $ar
}

# FIXME: Re-order captures when moved
# Capture a frame
# Sets $RESULT to the timestamp actually used
# capture($1 = filename, $2 = output file, $3 = second, [$4 = disable blank frame evasion])
capture() {
	trace $@
	local f=$1 out=$2 stamp=$3 prevent_evasion=$4
	local alternatives= alt= delta=
	if [[ $prevent_evasion != '1' ]]; then
		for delta in ${EVASION_ALTERNATIVES[@]} ; do
			alt=$(awkexf "$stamp + $delta")
			if fptest $alt -gt 0  && fptest $alt -lt "${VID[$LEN]}" ; then
				alternatives+=( $alt )
			fi
		done
	fi
	RESULT=
	capture_and_evade "$1" "$2" "$3" ${alternatives[*]} || {
		# Failed capture
		return $?
	}
	# Correct the timestamp in case it had to be adjusted
	local nstamp=$(echo "$CAPTURES" | tail -2 | head -1 | cut -d':' -f1)
	if fptest "int($stamp)" -ne "int($nstamp)" ; then
		inf "  Capture point changed to $( pretty_stamp $nstamp )"
		stamp=$nstamp
	fi
	RESULT=$stamp
}

# Capture a frame, retry a few times if a blank frame is detected. Use capture()
# Appends '$timestamp:$output\n' to $CAPTURES
# capture_and_evade($1 = filename, $2 = output file, $3 = second, $4... = alternate seconds)
capture_and_evade() {
	trace $@
	local f=$1 stamp=$3 ofile=$2
	shift 2
	local tscand=
	while [[ -n $1 ]]; do
		tscand=$1
		shift
		if ! capture_impl "$f" "$tscand" "$ofile" ; then
			error "Failed to capture frame at $(pretty_stamp $stamp) (${stamp}s)."
			return $EX_SOFTWARE
		fi
		# **XXX: EXPERIMENTAL: Blank frame evasion, initial test implementation
		local blank_val=$(convert "$ofile" -colorspace Gray -format '%[fx:image.mean*100]' info:)
		local upper=$(( 100 - $BLANK_THRESHOLD ))
		if fptest $blank_val -lt $BLANK_THRESHOLD || fptest $blank_val -gt $upper ; then
			local msg="  Blank (enough) frame detected."
			if [[ -n $1 ]]; then
				msg+=" Retrying at $(pretty_stamp $1)."
			else
				msg+=" Giving up."
			fi
			warn "$msg"
		else
			# No need to evade
			break
		fi
		# /XXX
	done
	CAPTURES="$CAPTURES$RESULT$NL"
}

# Capture a frame, intermediate-level implementation, use capture() instead.
# Sets $RESULT to '$timestamp:$output'
# Sets $CAPTURED_FROM_CACHE to 1 if it was already captured
# capture_impl($1 = filename, $2 = second, $3 = output file)
capture_impl() {
	trace $@
	local f=$1 stamp=$2 ofile=$3
	RESULT=''
	CAPTURED_FROM_CACHE=0

	# Avoid recapturing if timestamp is already captured.
	# The extended set includes the standard set so when using the extended mode
	#+this will avoid some captures, specially with mplayer, since it doesn't
	#+have ms precission
	# FIXME: This often won't work with ffmpeg since there might be a slight
	#        difference in ms.
	local key=
	# Normalise key values' decimals
	if [[ $CAPTURER_HAS_MS -eq 0 ]]; then
		key=$(awkex "int($stamp)")
	else
		key=$(awkex $stamp)
	fi
	local cached=$(grep "^$key:" <<<"$CAPTURES" | head -1)
	if [[ $cached ]]; then
		notice "Skipped capture at $(pretty_stamp $key)"
		cp "${cached#*:}" "$ofile" # TODO: Is 'cp -s' safe?
		CAPTURED_FROM_CACHE=1
	else
		local capfn=${CAPTURER}_capture
		if [[ $DVD_MODE -eq 1 ]]; then
			capfn=${CAPTURER}_dvd_capture
		fi
		$capfn "$f" "$stamp" "$ofile" || {
			return $EX_SOFTWARE
		}
	fi

	RESULT="$key:$ofile"
}

# Applies all individual vidcap filters
# filter_vidcap($1 = filename, $2 = timestamp, $3 = width, $4 = height, $5 = context, $6 = index[1..])
filter_vidcap() {
	trace $@
	# For performance purposes each filter adds a set of options
	# to 'convert'. That's less flexible but right enough now for the current
	# filters.
	local f=$1 t=$2 w=$3 h=$4 c=$5 i=$6
	local cmdopts=
	for filter in ${FILTERS_IND[@]}; do
		$filter "$f" "$t" "$w" "$h" "$c" "$i" # Sets $RESULT
		cmdopts="$cmdopts $RESULT -flatten "
	done
	local t=$(new_temp_file .png)
	eval "convert -background transparent -fill transparent '$1' $cmdopts '$t'"
	# If $t doesn't exist returns non-zero
	[[ -f $t ]] && mvq "$t" "$1"
}

# Applies all global vidcap filters
#filter_all_vidcaps() {
#	# TODO: Do something with "$@"
#	true
#}

filt_resize() {
	trace $@
	local f="$1" t=$2 w=$3 h=$4

	# Note the '!', required to change the aspect ratio
	RESULT=" \( -geometry ${w}x${h}! \) "
}

# Draw a timestamp in the file
# filt_apply_stamp($1 = filename, $2 = timestamp, $3 = width, $4 = height, $5 = context, $6 = index)
filt_apply_stamp() {
	trace $@
	local filename=$1 timestamp=$2 width=$3 height=$4 context=$5 index=$6

	local pts=$PTS_TSTAMPS
	if [[ $height -lt 200 ]]; then
		pts=$(( $PTS_TSTAMPS / 3 ))
	elif [[ $height -lt 400 ]]; then
		pts=$(( $PTS_TSTAMPS * 2 / 3 ))
	fi
	# If the size is too small they won't be readable at all
	# With the original font 8 was the minimum, with DejaVu 7 is readable
	if [[ $pts -le 7 ]]; then
		pts=7
		if [[ ( $index -eq 1 ) && ( $context -ne $CTX_EXT ) ]]; then
			warn "Very small timestamps in use. Disabling them with -dt might be preferable"
		fi
	fi
	# The last -gravity None is used to "forget" the previous gravity (otherwise it would
	# affect stuff like the polaroid frames)
	RESULT=" \( -box '$BG_TSTAMPS' -fill '$FG_TSTAMPS' -stroke none -pointsize '$pts' "
	RESULT+="    -gravity '$GRAV_TIMESTAMP' -font '$FONT_TSTAMPS' -strokewidth 3 -annotate +5+5 "
	RESULT+="    ' $timestamp ' \) -flatten -gravity None "
}

# Apply a framed photo-like effect
# Taken from <http://www.imagemagick.org/Usage/thumbnails/#polaroid>
# filt_photoframe($1 = filename, $2 = timestamp, $3 = width, $4 = height)
filt_photoframe() {
	trace $@
# Tweaking the size gives a nice effect too
# w=$(( $w - ( $RANDOM % ( $w / 3 ) ) ))
	# The border is relative to the input size (since 1.0.99), with a maximum of 6
	# Should probably be bigger for really big frames
	# Note that only images below 21600px (e.g. 160x120) go below a 6px border
	local border=$(( ($3*$4) / 3600 ))
	[[ $border -lt 7 ]] || border=6
	RESULT="-bordercolor white -border $border -bordercolor grey60 -border 1 "
}

filt_softshadow() {
	# Before this was a filter, there was the global (montage) softshadow (50x2+10+10) and the
	# photoframe inline softshadow 60x4+4+4
	RESULT="\( -background black +clone -shadow 50x2+4+4 -background none \) +swap -flatten -trim +repage "
}


# Apply a polaroid-like border effect
# Based on filt_photoframe(), with a bigger lower border
# filt_polaroid($1 = filename, $2 = timestamp, $3 = width, $4 = height)
filt_polaroid() {
	trace $@
	local border=$(( ($3*$4) / 3600 )) # Read filt_photoframe for details
	[[ $border -lt 7 ]] || border=6
	RESULT="\(  -fill white -background white "
	RESULT+="   -bordercolor white -mattecolor white -frame ${border}x${border} "
	# XXX: Double-flipping, there's surely a better way
	RESULT+="   \( -flip -splice 0x$(( $border*5 )) \) "
	RESULT+="   -flip -bordercolor grey60 -border 1 +repage "
	RESULT+="\)"
}

# Applies a random rotation
# Taken from <http://www.imagemagick.org/Usage/thumbnails/#polaroid>
# filt_randrot($1 = filename, $2 = timestamp, $3 = width, $4 = height)
filt_randrot() {
	trace $@
	# Rotation angle [-18..18]
	local angle=$(( ($(rand) % 37) - 18 ))
	RESULT="-background none -rotate $angle "
}

# Create the sprocket-holes pattern
# init_filt_film($1 = capture_width, $2 = capture_height)
init_filt_film() {
	trace $@
	[[ -z $FILMSTRIP ]] || return 0
	local w=$1 h=$2
	# Base reel dimensions
	#local rw=$(rmultiply $w,0.08) # 8% width
	local rw=51
	local rh=29
	local vspad=10 # Vertical padding between sprocket holes
	# Temporary files
	local reel_strip=$(new_temp_file -reel.png)
	local sprocket_mask=$(new_temp_file -smask.png)
	local sprocket=$(new_temp_file -sprocket.png)

	# Create the film reel pattern...
	local rw2=$(( $rw - 10 )) rh2=$(( $rh - 10 ))
	# Instead, create a big enough strip and then resize 
	local must_rescale=0
	if [[ ( $w -lt 240 ) || ( $h -lt 240 ) ]]; then
		must_rescale=1
	fi
	# I (still) don't know how to do it in a single step, moving the mask to
	# a parenthesised expression won't work, probably due to -alpha interactions
	# First step: Create a mask: Black border, rounded-corners transparent rectangle
	# (Source: http://www.imagemagick.org/Usage/thumbnails/#rounded)
	local r=4 # 8 -> much more rounded, still mostly rectangular
	convert -size ${rw2}x${rh2} 'xc:black' \
			\( +clone -alpha extract \
				-draw "fill black polygon 0,0 0,$r $r,0 fill white circle $r,$r $r,0" \
				\( +clone -flip \) -compose Multiply -composite \
				\( +clone -flop \) -compose Multiply -composite \
			\) -alpha off -compose CopyOpacity -composite \
		"$sprocket_mask"
	# Second step: Create a bigger rectangle and cut-out the mask above
	convert -size ${rw}x$(( ${rh} + ${vspad} )) 'xc:white' -gravity Center \
		"$sprocket_mask" -composite -alpha Copy -negate \
		"$sprocket"
	if [[ $must_rescale -eq 1 ]]; then
		rws=$(( $(rmultiply $w,0.08) ))
		rhs=$(( ( $rws * 4 ) / 7 ))
		convert "$sprocket" -geometry ${rws}x${rhs} "$sprocket"
		rh=$rhs
	fi
	# FIXME: Error handling
	# Repeat it until the height is reached and crop to the exact height
	local repeat=$( ceilmultiply $h/$rh )
	let 'repeat += 1'
	#$(yes -- '-clone 0 ( -size 1x5 xc:black ) ' | head -n $repeat) \
	#-append -crop ${rw}x${h}+0+0 \
	# Can't use "yes -- '-clone 0'" outside GNU
	convert -background black -fill black "$sprocket" \
		$(yes 'clone 0' | head -$repeat | sed 's/^/-/') \
		-append \
		"$reel_strip"
	FILMSTRIP=$reel_strip
	FILMSTRIP_HOLE_HEIGHT=$(imh "$sprocket")
}

# This one requires much more work, the results are pretty rough, but ok as
# a starting point / proof of concept
filt_film() {
	trace $@
	local file="$1" ts=$2 w=$3 h=$4
	init_filt_film $w $h
	assert "[[ -n '$FILMSTRIP' ]]"

	local skew=$(( $RANDOM % $FILMSTRIP_HOLE_HEIGHT ))

	# As this options will be appended to the commandline we cannot
	# order the arguments optimally (eg: reel.png image.png reel.png +append)
	# A bit of trickery must be done flipping the image. Note also that the
	# second strip will be appended flipped, which is intended.
	RESULT=" \( '$FILMSTRIP' -crop x${h}+0+$skew \) +append -flop "
	RESULT+="\( '$FILMSTRIP' -crop x${h}+0+$skew \) +append -flop "
}

# Creates a contact sheet by calling the delegate
# create_contact_sheet($1 = columns, $2 = context, $3 = width, $4 = height,
#                      $5...$# = vidcaps) : output
create_contact_sheet() {
	trace $@
	$CSHEET_DELEGATE "$@"
}

# This is the standard contact sheet creator
# csheet_montage($1 = columns, $2 = context, $3 = width, $4 = height,
#                $5... = vidcaps) : output
csheet_montage() {
	trace $@
	local cols=$1 ctx=$2 width=$3 height=$4 output=$(new_temp_file .png)
	shift 4
	# Padding is no longer dependant upong context since alignment of the
	# captures was far trickier then
	local hpad= vpad= splice=

	# The shadows already add a good amount of padding
	if has_filter filt_softshadow ; then
		hpad=0
		vpad=0
		splice=5x10
	else
		hpad=$PADDING
		vpad=$PADDING
		splice=0x8
	fi

	montage -background Transparent "$@" -geometry +$hpad+$vpad -tile "$cols"x "$output"
	convert "$output" -background Transparent -splice $splice "$output"

	# FIXME: Error handling
	echo $output
}

# Polaroid contact sheet creator: it overlaps vidcaps with some randomness
# csheet_overlap($1 = columns, $2 = context, $3 = width, $4 = height,
#                 $5... = $vidcaps) : output
csheet_overlap() {
	trace $@
	local cols=$1 ctx=$2 width=$3 height=$4
	# globals: $VID
	shift 4

	# TBD: Handle context

	# Explanation of how this works:
	# On the first loop we do what the "montage" command would do (arrange the
	# images in a grid) but overlapping each image to the one on their left,
	# creating the output row by row, each row in a file.
	# On the second loop we append the rows, again overlapping each one to the
	# one before (above) it.
	# XXX: Compositing over huge images is quite slow, there's probably a
	# better way to do it

	# Offset bounds, this controls how much of each snap will be over the
	# previous one. Note it is important to work over $width and not $VID[$W]
	# to cover all possibilities (extended mode and -H change the vidcap size)
	local maxoffset=$(( $width / 3 ))
	local minoffset=$(( $width / 6 ))

	# Holds the files that will form the full contact sheet
	# each file is a row on the final composition
	local -a rowfiles

	# Dimensions of the canvas for each row, it should be big enough
	# to hold all snaps.
	# My trigonometry is pretty rusty but considering we restrict the angle a lot
	# I believe no image should ever be wider/taller than the diagonal (note the
	# ceilmultiply is there to simply round the result)
	local diagonal=$(ceilmultiply $(pyth_th $width $height) 1)
	# XXX: The width, though isn't guaranteed (e.g. using filt_film it ends wider)
	#      adding 3% to the diagonal *should* be enough to compensate
	local canvasw=$(( ( $diagonal + $(rmultiply $diagonal,0.3) ) * $cols ))
	local canvash=$(( $diagonal ))

	# The number of rows required to hold all the snaps
	local numrows=$(ceilmultiply ${#@},1/$cols) # rounded division

	# Variables inside the loop
	local col       # Current column
	local rowfile   # Holds the row we're working on
	local offset    # Random offset of the current snap [$minoffset..$maxoffset]
	local accoffset # The absolute (horizontal) offset used on the next iteration
	local cmdopts   # Holds the arguments passed to convert to compose the sheet
	local w         # Width of the current snap
	for row in $(seqr 1 $numrows) ; do
		col=0
		rowfile=$(new_temp_file .png)
		rowfiles=( "${rowfiles[@]}" "$rowfile" )
		accoffset=0
		cmdopts= # This command is pretty time-consuming, let's make it in a row

		# Base canvas # Integrated in the row creation since 1.0.99

		# Step through vidcaps (col=[0..cols-1])
		for col in $(seqr 0 $(( $cols - 1 ))); do
			# More cols than files in the last iteration (e.g. -n10 -c4)
			if [[ -z $1 ]]; then break; fi
			w=$(imw "$1")

			# Stick the vicap in the canvas
			cmdopts="$cmdopts '$1' -geometry +${accoffset}+0 -composite "

			offset=$(( $minoffset + ( $(rand) % $maxoffset ) ))
			let 'accoffset=accoffset + w - offset'
			shift
		done
		inf "Composing overlapped row $row/$numrows..."
		eval convert -size ${canvasw}x${canvash} xc:transparent -geometry +0+0 "$cmdopts" -trim +repage "'$rowfile'" >&2
	done

	inf "Merging overlapped rows..."
	output=$(new_temp_file .png)

	cmdopts=
	accoffset=0
	local h
	for row in "${rowfiles[@]}" ; do
		w=$(imw "$row")
		h=$(imh "$row")
		minoffset=$(( $h / 8 ))
		maxoffset=$(( $h / 4 ))
		offset=$(( $minoffset + ( $(rand) % $maxoffset ) ))
		# The row is also offset horizontally
		cmdopts="$cmdopts '$row' -geometry +$(( $(rand) % $maxoffset ))+$accoffset -composite "
		let 'accoffset=accoffset + h - offset'
	done
	# After the trim the image will be touching the outer borders and the heading and footer,
	# older versions (prior to 1.0.99) used -splice 0x10 to correct the heading spacing, 1.0.99
	# onwards uses -frame to add spacing in all borders + splice to add a bit more space on the
	# upper border. Note splice uses the background colour while frame uses the matte colour
	eval convert -size ${canvasw}x$(( $canvash * $cols )) xc:transparent -geometry +0+0 \
		$cmdopts -trim +repage -bordercolor Transparent -background Transparent -mattecolor Transparent \
		-frame 5x5 -splice 0x5 "$output" >&2

	# FIXME: Error handling
	echo $output
}

# Sorts timestamps and removes duplicates
# clean_timestamps($1 = space separated timestamps)
clean_timestamps() {
	trace $@
	# Note sort works on lines, hence the stonl
	local s=$1
	echo "$s" | stonl | sort -n | uniq
}

# Test the video at a given timestamp (to see if it can be reached)
# See safe_length_measure()
# probe_video($1 = input file, $2 = stamp)
probe_video() {
	local f="$1"
	local ts="$2"
	local ret=0

	# This time a resize filter is applied to the player to produce smaller
	# output
	if [[ $DECODER -eq $DEC_MPLAYER ]]; then
		if ! mplayer_probe "$f" "$ts"; then
			ret=1
		fi
	elif [[ $DECODER -eq $DEC_FFMPEG ]]; then
		if ! ffmpeg_probe "$f" "$ts" ; then
			ret=1
		fi
	else
		assert false
		ret=1
	fi
	return $ret
}

# Try to guess a correct length for the video, taking the reported length as a
# starting point
# safe_length_measure($1 = filename)
safe_length_measure() {
	trace $@
	local f="$1"
	local len=${VID[$LEN]}
	local tempfile=
	local newlen=$len
	local capturefn=

	if probe_video "$1" $len ; then
		inf " File looks fine, suspicion withdrawn"
		echo "$len"
		return 0
	else
		# Can't seek to the very end, adjust
		warn "Starting safe length measuring (this might take a while)..."
		local maxrew=$(min $QUIRKS_MAX_REWIND $(awkex "int($len)"))  # At most we'll rewind 20 seconds
		# -1 (-WS) => Rewind up to the start
		# Might be -2, -4, ... e.g. (-WS -Ws)
		if fptest $maxrew -ge $len || fptest "$maxrew" -lt 0 ; then
			maxrew=$len
			INTERNAL_MAXREWIND_REACHED=1
		fi
		for rew in $(seqr $QUIRKS_LEN_STEP $maxrew $QUIRKS_LEN_STEP); do
			newlen=$(keepdecimals_lower $(awkexf "$len - $rew") 3)
			warn "   ... trying $(pretty_stamp $newlen)"
			if probe_video "$f" "$newlen" ; then
				echo $newlen
				return 0
			fi
		done
	fi
	# Hitting this line means we're doomed!
	return 1
}

##### {{{{ Codec names

# Codecs TODO: Clean this
# Translates an mplayer codec id/fourcc to its name
get_vcodec_name() {
	local vcid="$1"
	local vcodec=
	# Video codec "prettyfication", see [[R2]], [[R3]], [[R4]]
	case "$vcid" in
		0x10000001) vcodec="MPEG-1" ;;
		0x10000002) vcodec="MPEG-2" ;;
		0x00000000) vcodec="Raw video" ;; # How correct is this?
		# H264 is used in mov/mp4.
		# 0x07 was seen in mplayer 1.0rc2-4.2.1 (FreeBSD)
		0x00000007|avc1|H264) vcodec="MPEG-4 AVC" ;;
		DIV3) vcodec="DivX ;-) Low-Motion" ;; # Technically same as mp43
		DX50) vcodec="DivX 5" ;;
		FMP4) vcodec="FFmpeg" ;; # XXX: Would LAVC be a better name?
		I420) vcodec="Raw I420 Video" ;; # XXX: Officially I420 is Indeo 4 but it is mapped to raw ¿?
		MJPG) vcodec="M-JPEG" ;; # mJPG != MJPG
		MPG4) vcodec="MS MPEG-4 V1" ;;
		MP42) vcodec="MS MPEG-4 V2" ;;
		MP43) vcodec="MS MPEG-4 V3" ;;
		RV10) vcodec="RealVideo 1.0/5.0" ;;
		RV20) vcodec="RealVideo G2" ;;
		RV30) vcodec="RealVideo 8" ;;
		RV40) vcodec="RealVideo 9/10" ;;
		SVQ1) vcodec="Sorenson Video 1" ;;
		SVQ3) vcodec="Sorenson Video 3" ;;
		theo) vcodec="Ogg Theora" ;;
		tscc) vcodec="TechSmith SCC" ;;
		VP6[012F]) vcodec="On2 Truemotion VP6" ;;
		VP80) vcodec="VP8" ;;
		WMV1) vcodec="WMV7" ;;
		WMV2) vcodec="WMV8" ;;
		WMV3) vcodec="WMV9" ;;
		WMVA) vcodec="WMV9 Advanced Profile" ;; # Not VC1 compliant. Deprecated by Microsoft.
		XVID) vcodec="Xvid" ;;
		3IV2) vcodec="3ivx Delta 4.0" ;; # Rare but seen
		FLV1) vcodec="Sorenson Spark (FLV1)" ;;
		FPS1) vcodec="Fraps" ;;

		# These are known FourCCs that I haven't tested against so far
		WVC1) vcodec="VC-1" ;;
		DIV4) vcodec="DivX ;-) Fast-Motion" ;;
		DIVX|divx) vcodec="DivX" ;; # OpenDivX / DivX 5(?) / Project Mayo
		IV4[0-9]) vcodec="Indeo Video 4" ;;
		IV50) vcodec="Indeo 5.0" ;;
		VP3[01]) vcodec="On2 VP3" ;;
		VP40) vcodec="On2 VP4" ;;
		VP50) vcodec="On2 VP5" ;;
		s263) vcodec="H.263" ;; # 3GPP
		# Legacy(-er) codecs (haven't seen files in these formats in awhile)
		IV3[0-9]) vcodec="Indeo Video 3" ;; # FF only recognises IV31
		MSVC) vcodec="Microsoft Video 1" ;;
		MRLE) vcodec="Microsoft RLE" ;;
		3IV1) vcodec="3ivx Delta" ;;
		# "mp4v" is the MPEG-4 fourcc *in mov/mp4/3gp*; but I also found MP4V (Apple's iTunes sample)
		mp4v|MP4V) vcodec="MPEG-4" ;;
		# Synthetic, used for ffmpeg translations
		vcs_divx) vcodec="DivX ;-)" ;;
		# Allow both the synthetic (for older mplayer) and builtin (for newer mplayer) codec ids
		vcs_hevc|HEVC) vcodec="HEVC" ;;
		vcs_vp9|VP90) vcodec="VP9" ;; # VP9 was detected as rawyuy2 by older MPlayer
		*) # If not recognized fall back to FourCC
			vcodec="$vcid"
			;;
	esac
	echo "$vcodec"
}

# Translates an FFmpeg codec id to an MPlayer codec id/fourcc
# TODO: Clean this
translate_ffmpeg_vcodec_id() {
	# The list of ffmpeg codecs might be retrieved by looking at the code but I
	#+simply used the ffmpeg -formats / ffmpeg -codecs command
	# Supported video decoders: $ ffmepg -codecs | grep '^ D.V'
	local vcid="$1"
	local mpid=
	case "$vcid" in
		mpeg1video) mpid="0x10000001" ;; # mpeg1video_vdpau?
		mpeg2video) mpid="0x10000002" ;;
		rawvideo)   mpid="0x00000000" ;; # can't distinguish from I420
		h264)       mpid="avc1" ;;
		mjpeg)      mpid="MJPG" ;;
		msmpeg4v1)  mpid="MPG4" ;;
		msmpeg4v2)  mpid="MP42" ;;
		theora)     mpid="theo" ;;
		camtasia)   mpid="tscc" ;;
		vp6|vp6a|vp6f) mpid="VP60" ;;
		vp8) mpid="VP80" ;;
		# HEVC and VP9 weren't supported by older versions MPlayer
		#   Seen:
		#    "hevc (Main) (HEVC / 0x43564548)" in MPEG2-TS
		#    "hevc" in h.265 ES
		# TODO: Enforce a minimum version of mplayer
		hevc|hevc\ *) mpid="vcs_hevc" ;;
		vp9)          mpid="vcs_vp9" ;;
		# TODO List of codec id's I translate but haven't tested:
		#+ svq3, rv40, theora, camtasia, vp6*
		# MPlayer uses uppercase whereas FFmpeg uses lowercase
		rv10|rv20|rv30|rv40|svq1|svq3|wmv1|wmv2|wmv3) mpid=$(echo $vcid | tr a-z A-Z) ;;
		# FFmpeg doesn't print FourCC's so there's some codecs that can't be told apart
		msmpeg4)    mpid="vcs_divx" ;; # DIV3 = DIV4 = MP43
		# XVID = DIVX = DX50 = FMP4 = ... = mpeg4
		mpeg4)      mpid="mp4v" ;; # Take advantage of an unamed MPEG-4

		h263)       mpid="s263" ;;

		vc1)        mpid="WVC1" ;; # In FF: WMVA = vc1
		flv)        mpid="FLV1" ;;
		fraps)      mpid="FPS1" ;;
		# Not supported (ff just prints the FourCC)
		# IV4*, vp4
		vp3) mpid="VP30" ;;
		vp5) mpid="VP50" ;;
		# Legacy(-er) codecs (haven't seen files in these formats in awhile)
		# MSVC? MRLE?
		indeo3) mpid="IV31" ;;
		*) # If not recognized fall back to FourCC
			mpid="$vcid"
			;;

	esac
	echo $mpid
}

get_acodec_name() {
	local acid="$1"
	local acodec=

	local ERE='[ -]'
	if [[ $acid =~ $ERE ]]; then
		# Won't be recognised anyway
		echo "$acid"
		return
	fi

	case "$(tolower "$acid")" in
		85) acodec='MPEG Layer III (MP3)' ;;
		80) acodec='MPEG Layer I/II (MP1/MP2)' ;; # Apparently they use the same tag
		mp4a) acodec='MPEG-4 AAC' ;; # LC and HE, apparently
		352) acodec='WMA7' ;; # =WMA1
		353) acodec='WMA8' ;; # =WMA2 No idea if lossless can be detected
		354) acodec='WMA9' ;; # =WMA3
		8192) acodec='AC3' ;;
		1|65534)
			# 1 is standard PCM (apparently all sample sizes)
			# 65534 seems to be multichannel PCM
			acodec='Linear PCM' ;;
		vrbs|22127)
			# 22127 = Vorbis in AVI (with ffmpeg). DON'T!
			# vrbs = Vorbis in Matroska, Ogg, probably others
			acodec='Vorbis'
			;;
		qdm2) acodec="QDesign" ;;
		"") acodec="no audio" ;;
		samr) acodec="AMR" ;; # AMR-NB/AMR-WB?
		# Following not seen by me so far, don't even know if mplayer would
		# identify them
		#<http://lists.mplayerhq.hu/pipermail/ffmpeg-devel/2005-November/005054.html>
		355) acodec="WMA9 Lossless" ;;
		10) acodec="WMA9 Voice" ;;
		# Other versions of R.A. listed at Wikipedia/RealAudio
		sipr) acodec="RealAudio SIPR" ;; # RA 4/5
		cook) acodec="RealAudio Cook" ;; # RA 6
		*) # If not recognized show audio id tag
			acodec="$acid"
			;;
	esac
	echo "$acodec"
}

translate_ffmpeg_acodec_id() {
	local acid="$1"
	local mpid=
	
	# ffmpeg -codecs | grep ^\ D.A
	case "$acid" in
		mp3)    mpid='85' ;;
		# Note FF can tell apart mp1/mp2 directly
		mp1)    mpid='MPEG Layer I (MP1)' ;;
		mp2)    mpid='MPEG Layer II (MP2)' ;;
		aac)    mpid='mp4a' ;; # Can aac be MPEG2?
		wmav1)  mpid='352' ;;
		wmav2)  mpid='353' ;;
		wmapro) mpid='354' ;; # Actually WMA9 Professional
		ac3)    mpid='8192' ;;
		# FF has a ton of pcm variants (sign, endianness, ...)
		pcm_*)  mpid="1" ;;
		vorbis) mpid="vrbs" ;;

		qdm2)   mpid="QDM2" ;;
		libopencore_amrnb) mpid="AMR-NB" ;;
		libopencore_amrwb) mpid="AMR-WB" ;;
		*) # If not recognized show audio id tag
			mpid="$acid"
			;;
	esac
	echo "$mpid"
}

##### }}}} # Codec names

### {{{ Modularisation/abstraction of video capturers, TODO: work in progress

check_avail_tools() {
	local capturer='' identifier='' fn=
	for capturer in ${CAPTURERS[*]}; do
		fn=${capturer}_test_avail
		is_defined $fn || continue
		if $fn ; then
			CAPTURERS_AVAIL=( "${CAPTURERS_AVAIL[@]}" "$capturer" )
		fi
	done
	for identifier in ${IDENTIFIERS[*]}; do
		fn=${identifier}_test_avail
		is_defined $fn || continue
		if $fn ; then
			IDENTIFIERS_AVAIL=( "${IDENTIFIERS_AVAIL[@]}" $identifier )
		fi
	done
	CAPTURER=${CAPTURERS_AVAIL[0]}
	IDENTIFIER=${IDENTIFIERS_AVAIL[0]}

	if [[ ( -z $CAPTURER ) || ( -z $IDENTIFIER ) ]]; then
		error "No supported video tools (mplayer, ffmpeg) available"
		return $EX_UNAVAILABLE
	fi
}

pick_tools() {
	trace $@
	# User *wants* a certain decoder
	if [[ $USR_CAPTURER ]]; then
		if ! grep -qi "$CAPTURER" <<<"${CAPTURERS_AVAIL[@]}" ; then
			error "User selected capturing tool ($CAPTURER) is not available"
			return $EX_UNAVAILABLE
		fi
	fi

	# DVD mode is optional, and since 1.12 DVD mode can work with multiple inputs too
	# DVD Mode only works with mplayer, the decoder is changed when
	# the DVD mode option is found, so if it's ffmpeg at this point,
	# it's by user request (i.e. -F after -V)
	if [[ $DVD_MODE -eq 1 ]] && ! is_defined "${CAPTURER}_dvd_capture" ; then
		# Pick the first available dvd capturer, if any
		CAPTURER=
		local c=
		for c in "${CAPTURERS_AVAIL[@]}"; do
			if is_defined "${c}_dvd_capture" ; then
				CAPTURER="$c"
				break;
			fi
		done
		if [[ -z $CAPTURER ]]; then
			# None available with DVD support
			error "No available capturer has DVD support"
			return $EX_UNAVAILABLE
		fi
		if [[ $USR_CAPTURER != $CAPTURER ]]; then
			# User choose one, we can't use
			warn "$(tolower $USR_CAPTURER) can't capture in DVD mode, switching to $CAPTURER"
		fi
	fi

	# Propagate to the related settings
	local actual=$CAPTURER
	[[ -z $USR_CAPTURER ]] || set_capturer $USR_CAPTURER 1 # Preferred
	set_capturer $actual 0 # Actual
}

### }}}

# Classic identification, uses mplayer and ffmpeg
# Use the available tools to identify video meta-data
# fills $VID with the values
# Return codes:
#   3: Failed to detect length
#   4: Failed to detect width or height
# classic_identify($1 = file)
classic_identify() {
	trace $@
	local RET_NOLEN=3 RET_NODIM=4

	assert '[[ $MPLAYER_BIN && $FFMPEG_BIN ]]'
	assert 'is_defined mplayer_identify && is_defined ffmpeg_identify'

	mplayer_identify "$1" 2>/dev/null

	# ffmpeg_identify in DVD mode only works when the DVD is mounted:
	[[ ( $DVD_MODE -eq 0 ) && ( $FFMPEG_BIN ) ]] && ffmpeg_identify "$1"
	[[ ( $DVD_MODE -eq 1 ) && ( $FFMPEG_BIN ) && ( $DVD_MOUNTP ) ]] && ffmpeg_identify "$1"

	local fid=( "${FFMPEG_ID[@]}" )
	# Fail early if none detected length
	[[ ( -z ${MPLAYER_ID[$LEN]} ) && ( -z ${FFMPEG_ID[$LEN]} ) ]] && return $RET_NOLEN

	# By default take mplayer's values
	VID=( "${MPLAYER_ID[@]}" )
	# FFmpeg seems better at getting the correct number of FPS, specially with
	# WMVs, where mplayer often accepts 1000fps while ffmpeg notices the
	# inconsistency in container vs codec and guesses better, *but* it only
	# uses two decimals so 23.976 becomes 23.98. So it is only used when
	# the number of decimals seems right.
	# When a "Seems..." line is printed the correct FPS can be obtained though.
	[[ -z ${MPLAYER_ID[$FPS]} ]] && VID[$FPS]=${fid[$FPS]}
	[[ ${MPLAYER_ID[$FPS]} && ${fid[$FPS]} ]] && {
		# Trust ffmpeg if it has three decimals OR if mplayer is probably-wrong
		local ffps=${fid[$FPS]}
		local ERE='\.[0-9][0-9][0-9]'
		if [[ $ffps =~ $ERE ]]; then
			VID[$FPS]=$ffps
		elif fptest "${MPLAYER_ID[$FPS]}" -gt 500; then
			VID[$FPS]=$ffps
		fi
	}
	# It doesn't appear to need any workarounds for num. channels either
	[[ ${fid[$CHANS]} ]] && VID[$CHANS]=${fid[$CHANS]}
	[[ ${fid[$ASPECT]} ]] && VID[$ASPECT]=${fid[$ASPECT]}
	# There's a huge inconsistency with some files, both mplayer vs ffmpeg
	# and same application on different OSes
	local fflen=${fid[$LEN]} mplen=${MPLAYER_ID[$LEN]} # Shorthands
	# If the decoder can't seek there's no point in continuing
	if [[ ( ( $DECODER -eq $DEC_FFMPEG ) && ( -z $fflen ) ) ||
		  ( ( $DECODER -eq $DEC_MPLAYER ) && ( -z $mplen ) ) ]];
	then
		warn "$CAPTURER didn't report a length, seeking won't be possible."
		return $RET_NOLEN
	fi
	[[ -z $fflen ]] && fflen=0
	[[ -z $mplen ]] && mplen=0
	# If both report 0, there's no good value...
	fptest "$fflen" -eq 0 && fptest "$mplen" -eq 0 && return $RET_NOLEN

	if [[ ( $DVD_MODE -eq 0 ) && ( $QUIRKS -eq 0 ) ]]; then # In DVD mode ffmpeg has no length
		# Quirks disabled, should be enabled?
		local delta=$(abs $(awkexf "($fflen - $mplen)"))
		# If they don't agree, take the shorter as a starting point,
		#+if both are different than zero take min, if one of them is 0, take max to start
		if fptest "$fflen" -ne 0 && fptest "$mplen" -ne 0 ; then
			VID[$LEN]=$(min $fflen $mplen)
		else
			VID[$LEN]=$(max $fflen $mplen)
			delta=$QUIRKS_LEN_THRESHOLD # Ensure it's considered inconsistent
		fi
		# If they differ too much, enter safe mode. If one reports 0, they'll differ...
		# FIXME: If $DECODER reports 0, can it seek??
		if fptest "$delta" -ge $QUIRKS_LEN_THRESHOLD ; then
			warn "Found inconsistency in reported length. Safe measuring enabled."
			QUIRKS=1
		fi
	fi

	# Ensure sanity of the most important values
	is_float "${VID[$LEN]}" || return $RET_NOLEN
	is_number "${VID[$W]}" && is_number "${VID[$H]}" || {
		# Fall back to ffmpeg's dimensions
		VID[$W]=${FFMPEG_ID[$W]}
		VID[$H]=${FFMPEG_ID[$H]}
		is_number "${VID[$W]}" && is_number "${VID[$H]}" || return $RET_NODIM
	}
	# Mplayer can identify video as 0x0
	if [[ ${VID[$W]} -eq 0 ]]; then
		VID[$W]=${FFMPEG_ID[$W]}
	fi
	if [[ ${VID[$H]} -eq 0 ]]; then
		VID[$H]=${FFMPEG_ID[$H]}
	fi
	is_number "${VID[$W]}" && is_number "${VID[$H]}" || return $RET_NODIM
	[[ ${VID[$W]} -gt 0 ]] && [[ ${VID[$H]} -gt 0 ]] || return $RET_NODIM

	# FPS at least with two decimals
	if [[ $(awkex "int(${VID[$FPS]})") ==  "${VID[$FPS]}" ]]; then
		VID[$FPS]="${VID[$FPS]}.00"
	fi
	# MPlayer tends to identify as raw video if it doesn't support the codec
	# fall back to FFmpeg in such case
	if [[ ${MPLAYER_ID[$VCODEC]} = "0x00000000" ]]; then
		VID[$VCODEC]=${FFMPEG_ID[$VCODEC]}
		VID[$VCNAME]=${FFMPEG_ID[$VCNAME]}
	fi

	local mfps="${MPLAYER_ID[$FPS]}"
	if [[ ( $QUIRKS -eq 0 ) && ( -n $MPLAYER_BIN ) ]] && fptest "$mfps" -eq 1000 ; then
		warn "Suspect file. Safe measuring enabled."
		QUIRKS=1
	fi

	# Last safeguard: Try to reach the detected length, if it fails, trigger
	# quirks mode
	if [[ $QUIRKS -eq 0 ]]; then
		if ! probe_video "$1" "${VID[$LEN]}" ; then
			warn "Detected video length can't be reached. Safe measuring enabled."
			QUIRKS=1
		fi
	fi

	if [[ $QUIRKS -eq 1 ]]; then
		VID[$LEN]=$(safe_length_measure "$1")
		if [[ -z ${VID[$LEN]} ]]; then
			error "Couldn't measure length in a reasonable amount of tries."
			if [[ $INTERNAL_MAXREWIND_REACHED -eq 1 ]]; then
				error "  Will not be able to capture this file with the current settings."
			else
				local reqs=$(( $INTERNAL_WS_C + 1 )) reqp=''
				[[ $reqs -eq 1 ]] && reqp=" -WP" || reqp=" -WP$reqs"
				[[ $reqs -ge 3 ]] && reqs=" -WS" || { # Third try => Recommend -WS
					[[ $reqs -eq 1 ]] && reqs=" -Ws" || reqs=" -Ws$reqs"
				}
				assert 'fptest "$QUIRKS_MAX_REWIND" -gt 0'
				local offby=$(pretty_stamp $QUIRKS_MAX_REWIND)
				warn "  Capturing won't work, video is at least $offby shorter than reported."
				warn "   Does $CAPTURER support ${VID[$VCODEC]}?."
				warn "   Try re-running with$reqs$reqp."
			fi
			return 1
		fi
	elif [[ $QUIRKS -eq -2 ]]; then
		warn "Safe mode disabled."
	fi

	# Re-check sanity of the most important values
	is_float "${VID[$LEN]}" || return $RET_NOLEN

	RESULT=( "${VID[@]}" )
}

# Use the selected identifier to extract video meta-data
# fills $VID with the values
# Return codes:
#   3: Failed to detect length
#   4: Failed to detect width or height
# identify_video($1 = file)
identify_video() {
	${IDENTIFIER}_identify "$1"
	local ret=$?
	VID=( "${RESULT[@]}" )
	return $ret
}

dump_idinfo() {
	trace $@
	[[ $MPLAYER_BIN ]] && echo "Mplayer: $MPLAYER_BIN"
	[[ $FFMPEG_BIN  ]] && echo "FFmpeg:  $FFMPEG_BIN"
	local mpplen=
	[[ -z "${MPLAYER_ID[${LEN}]}" ]] || mpplen=$(pretty_stamp ${MPLAYER_ID[$LEN]})
	[[ $MPLAYER_BIN ]] && cat <<-EODUMP
	=========== Mplayer Identification ===========
	Length: $mpplen
	Video
	    Codec: ${MPLAYER_ID[$VCODEC]} (${MPLAYER_ID[$VCNAME]})
	    Dimensions: ${MPLAYER_ID[$W]}x${MPLAYER_ID[$H]}
	    FPS: ${MPLAYER_ID[$FPS]}
	    Aspect: ${MPLAYER_ID[$ASPECT]}
	Audio
	    Codec: ${MPLAYER_ID[$ACODEC]} (${MPLAYER_ID[$ACNAME]})
	    Channels: ${MPLAYER_ID[$CHANS]}
	==============================================

EODUMP
	local ffl="${FFMPEG_ID[$LEN]}"
	[[ $ffl ]] && ffl=$(pretty_stamp "$ffl")
	if [[ ( -z $ffl ) && ( $DVD_MODE -eq 1 ) ]]; then
		ffl="(unavailable in DVD mode)"
	fi
	[[ $FFMPEG_BIN ]] && cat <<-EODUMP
	=========== FFmpeg Identification ===========
	Length: $ffl
	Video
	    Codec: ${FFMPEG_ID[$VCODEC]} (${FFMPEG_ID[$VCNAME]})
	    Dimensions: ${FFMPEG_ID[$W]}x${FFMPEG_ID[$H]}
	    FPS: ${FFMPEG_ID[$FPS]}
	    Aspect: ${FFMPEG_ID[$ASPECT]}
	Audio
	    Codec: ${FFMPEG_ID[$ACODEC]} (${FFMPEG_ID[$ACNAME]})
	    Channels: ${FFMPEG_ID[$CHANS]}
	=============================================

EODUMP
	local xar=
	if [[ ${VID[$ASPECT]} ]]; then
		xar=$(keepdecimals "${VID[$ASPECT]}" 4)
		[[ $xar ]] && xar=" ($xar)"
	fi
	local clen=
	[[ -z ${VID[$LEN]} ]] || clen=$(pretty_stamp ${VID[$LEN]})
	cat <<-EODUMP
	=========== Combined Identification ===========
	Length: $clen
	Video
	    Codec: ${VID[$VCODEC]} (${VID[$VCNAME]})
	    Dimensions: ${VID[$W]}x${VID[$H]}
	    FPS: ${VID[$FPS]}
	    Aspect: ${VID[$ASPECT]}$xar
	Audio
	    Codec: ${VID[$ACODEC]} (${VID[$ACNAME]})
	    Channels: ${VID[$CHANS]}
	=============================================
EODUMP

}

# Try to pick some font capable of handling non-latin text
set_extended_font() {
	trace $@
	# This selection includes japanese fonts
	local candidates=$(identify -list font | grep 'Font: ' | \
						egrep -io '[a-z-]*(kochi|mincho|sazanami|ipafont)[a-z-]*')
	if [[ -z $candidates ]]; then
		error "Unable to auto-select filename font, please provide one (see -fullhelp)"
		return 1
	else
		if [[ $DEBUG -eq 1 ]]; then
			local list=$(echo "$candidates" |  sed 's/^/  >/g')
			inf "Available non-latin fonts detected:$NL$list"
		fi
	fi

	# Bias towards the Sazanami family
	shopt -s nocasematch
	local ERE='sazanami'
	if [[ $candidates =~ $ERE ]]; then
		NONLATIN_FONT=$(grep -i 'sazanami' <<<"$candidates" | head -1)
	else
		NONLATIN_FONT=$(head -1 <<<"$candidates")
	fi
	shopt -u nocasematch
}

# Checks if the provided arguments make sense and are allowed to be used
#+together. When an incoherence is found, sets some sane values if reasonable
#+or fails otherwise.
coherence_check() {
	trace $@
	# If -m is used then -S must be used
	if [[ ( $MANUAL_MODE -eq 1 ) && ( -z $INITIAL_STAMPS ) ]]; then
		error "You must provide timestamps (-S) when using manual mode (-m)"
		return $EX_USAGE
	fi

	# In case it's 0/0 or 0.0 since they aren't rejected
	if fptest "$EXTENDED_FACTOR" -eq 0 ; then
		EXTENDED_FACTOR=0
	fi

	if [[ ( $DECODER -eq $DEC_MPLAYER ) && ( -z $MPLAYER_BIN ) ]]; then
		inf "Mplayer not available."
		set_capturer ffmpeg 0
	elif [[ ( $DECODER -eq $DEC_FFMPEG ) && ( -z $FFMPEG_BIN ) ]]; then
		inf "FFmpeg not available."
		set_capturer mplayer 0
	fi

	local filter=
	local -a filts=( )
	if [[ $DISABLE_TIMESTAMPS -eq 0 ]] &&
			has_filter filt_polaroid && has_filter filt_apply_stamp ; then

			for filter in ${FILTERS_IND[@]} ; do
				if [[ $filter == 'filt_polaroid' ]]; then
					filts=( "${filts[@]}" "$filter" filt_apply_stamp )
				elif [[ $filter == 'filt_apply_stamp' ]]; then
					continue;
				else
					filts=( "${filts[@]}" $filter )
				fi
			done
			FILTERS_IND=( "${filts[@]}" )
			unset filts
	fi
	# The shoftshadow and randrot filters must be in the correct place
	# or they will affect the image incorrectly.
	# Additionally the default filters can be disabled from the command
	# line (with --disable), they're removed from the filter chain here
	local -a filts=( ) end_filts=( )
	for filter in ${FILTERS_IND[@]} ; do
		case "$filter" in
			filt_softshadow)
				# Note the newer soft shadows code (1.0.99 onwards) behaves slightly
				# differently. On previous versions disabling shadows only affected
				# the montage shadow (but e.g. the polaroid mode preserved them),
				# this is no longer true
				if [[ $DISABLE_SHADOWS -ne 1 ]]; then
					end_filts[100]="filt_softshadow"
				fi
				;;
			filt_apply_stamp)
				if [[ $DISABLE_TIMESTAMPS -ne 1 ]]; then
					filts=( "${filts[@]}" "$filter" )
				fi
				;;
			filt_randrot) end_filts[200]="filt_randrot" ;;
			*) filts=( "${filts[@]}" "$filter" ) ;;
		esac
	done
	FILTERS_IND=( "${filts[@]}" "${end_filts[@]}" )

	# Interval=0 == default interval
	fptest "$INTERVAL" -eq 0 && interval=$DEFAULT_INTERVAL

	# If in non-latin mode and no nonlatin font has been picked try to pick one.
	# Should it fail, fallback to latin font.
	if [[ ( $NONLATIN_FILENAMES -eq 1 ) && ( -z $NONLATIN_FONT ) ]]; then
		set_extended_font || {
			# set_extended_font already warns about lack of fonts
			warn "    Falling back to latin font"
			NONLATIN_FILENAMES=0
			NONLATIN_FONT="$FONT_HEADING"
		}
	fi

	sanitise_fonts
}

# If the OS hasn't registered TTF fonts with IM, try to use a saner value
#+*only* for fonts not overridden
sanitise_fonts() {
	trace $@

	# Any default font in use? If all of them are overridden, return
	if [[ $USR_FONT_HEADING && $USR_FONT_TITLE && \
			$USR_FONT_TSTAMPS && $USR_FONT_SIGN ]]; then
		return
	fi
	# If the user edits any font in the script, stop messing with this
	[[ ( -z $USR_FONT_HEADING ) && ( $FONT_HEADING != 'DejaVu-Sans-Book' ) ]] && return
	[[ ( -z $USR_FONT_TITLE ) && ( $FONT_TITLE != 'DejaVu-Sans-Book' ) ]] && return
	[[ ( -z $USR_FONT_TSTAMPS ) && ( $FONT_TSTAMPS != 'DejaVu-Sans-Book' ) ]] && return
	[[ ( -z $USR_FONT_SIGN ) && ( $FONT_SIGN != 'DejaVu-Sans-Book' ) ]] && return
	# Try to locate DejaVu Sans
	local dvs=''
	if [[ -d /usr/local/share/fonts ]]; then
		dvs=$(find /usr/local/share/fonts/ -type f -iname 'dejavusans.ttf')
	fi
	if [[ ( -z $dvs ) && ( -d /usr/share/fonts ) ]]; then
		dvs=$(find /usr/share/fonts/ -type f -iname 'dejavusans.ttf')
	fi
	if [[ -z $dvs ]]; then
		warn "Unable to locate DejaVu Sans font. Falling back to helvetica."
		dvs=helvetica
	fi
	[[ -z $USR_FONT_HEADING ]] && FONT_HEADING="$dvs"
	[[ -z $USR_FONT_TITLE ]] && FONT_TITLE="$dvs"
	[[ -z $USR_FONT_TSTAMPS ]] && FONT_TSTAMPS="$dvs"
	[[ -z $USR_FONT_SIGN ]] && FONT_SIGN="$dvs"
	[[ $DEBUG -eq 1 ]] || { return 0; }
	cat >&2 <<-EOFF
	Font Sanitation:
	  font_heading: $FONT_HEADING
	  font_title  : $FONT_TITLE
	  font_tstamps: $FONT_TSTAMPS
	  font_sign   : $FONT_SIGN
EOFF
}

# Main function.
# Creates the contact sheet.
# process($1 = file)
process() {
	trace $@
	local f=$1

	local numcols=
	# Save variables that will be overwritten and must be reset with multiple files
	# pre_* will contain the user-supplied or default values
	local pre_quirks=$QUIRKS
	local pre_aspect_ratio=$ASPECT_RATIO
	local pre_format="$FORMAT"
	INTERNAL_MAXREWIND_REACHED=0 # Reset for each file
	CAPTURES=''
	FILMSTRIP='' # Reset

	DVD_MOUNTP= DVD_TITLE= # Re-set for each file
	if [[ $DVD_MODE -eq 1 ]]; then
		local dvdn=$(realpathr "$f")
		# Is it an ISO?
		if [[ -f $dvdn ]]; then
			DVD_MOUNTP=$(get_dvd_image_mountpoint "$dvdn")
			if [[ -z $DVD_MOUNTP ]]; then
				# Only in Linux does this matter
				if ! is_linux ; then
					warn "Video properties detection for ISO files is not accurate"
				else
					warn "Mount DVD image to get better video properties detection"
				fi
			fi
		else
			# It's a device. Note BSD has no concept of block devices.
			# It MUST be mounted to continue. This is required to allow ffmpeg detection
			#+and to calculate file size
			if ! mount | egrep -q "^$dvdn\ " ; then
				error "DVD mode requires device ($f) to be mounted"
				return $EX_UNAVAILABLE
			fi
			DVD_MOUNTP=$(mount | grep -o "^$dvdn *on [^ ]*" | cut -d' ' -f3)
			dvdn="DVD $f"
		fi
		if [[ ! -r $f ]]; then
			error "Can't access DVD ($f)"
			return $EX_NOINPUT
		fi

		inf "Processing $dvdn..."
		unset dvdn
		DVD_TITLE=${DVD_TITLES[0]}
		DVD_TITLES=( "${DVD_TITLES[@]:1}" ) # shift array
		if [[ ( -z $DVD_TITLE ) || ( $DVD_TITLE == '0' ) ]]; then
			local dt="$(lsdvd "$f" 2>/dev/null | grep 'Longest track:' | \
							cut -d' ' -f3- | sed 's/^0*//')"
			if ! is_number "$dt" ; then
				error "Failed to autodetect longest DVD title for '$f'"
				exit $EX_INTERNAL
			fi
			DVD_TITLE=$dt
			unset dt
		fi
		DVD_VTS=$(lsdvd -t$DVD_TITLE -v "$f" 2>/dev/null | grep -o 'VTS: [0-9]*' | cut -d' ' -f2)
		inf "Using DVD Title #$DVD_TITLE (VTS: $DVD_VTS) for '$f'"
	else # Not DVD Mode:
		if [[ ! -f $f ]]; then
			error "File \"$f\" doesn't exist"
			return $EX_NOINPUT
		fi

		inf "Processing $f..."
	fi

	create_temp_dir
	# {{SET_E}} Beware, set -e will break this
	identify_video "$f"
	local ecode=$?
	[[ $ecode -eq 0 ]] || {
		case $ecode in
			3) error "Unable to find length of file \"$f\". Can't continue." ;;
			4) error "Unable to detect dimensions of file \"$f\". Can't continue." ;;
			*) error "Failure while analysing file \"$f\". Can't continue." ;;
		esac
		return $EX_UNAVAILABLE
	}

	# Identification-only mode?
	[[ $UNDFLAG_IDONLY ]] && dump_idinfo && return 0

	# Vidcap/Thumbnail height
	local vidcap_height=$HEIGHT
	if is_percentage "$HEIGHT" && [[ $HEIGHT != '100%' ]]; then
		vidcap_height=$(rpercent ${VID[$H]} ${HEIGHT})
		inf "Height: $HEIGHT of ${VID[$H]} = $vidcap_height"
	fi
	if ! is_number "$vidcap_height" || [[ $vidcap_height -eq 0 ]]; then
		vidcap_height=${VID[$H]}
	fi
	# -2: DVD Mode autodetection => If ffmpeg/mplayer was unable autodetect, otherwise
	#+ honor detected value
	if [[ $ASPECT_RATIO -eq -2 ]]; then
		[[ ${VID[$ASPECT]} ]] && ASPECT_RATIO=0 || ASPECT_RATIO=-1
	elif [[ $ASPECT_RATIO -eq 0 ]]; then
		if [[ ${VID[$ASPECT]} ]]; then
			# Aspect ratio in file headers, honor it
			ASPECT_RATIO=$(awkexf "${VID[$ASPECT]}")
		else
			ASPECT_RATIO=$(awkexf "${VID[$W]} / ${VID[$H]}")
		fi
	elif [[ $ASPECT_RATIO -eq -1 ]]; then
		ASPECT_RATIO=$(guess_aspect ${VID[$W]} ${VID[$H]})
		inf "Aspect ratio set to $ASPECT_RATIO."
	fi
	local vidcap_width=$(compute_width $vidcap_height)

	local nc=$NUMCAPS

	unset TIMECODES
	# Compute the stamps (if in auto mode)...
	if [[ $MANUAL_MODE -eq 1 ]]; then
		# Note TIMECODES must be set as an array to get the correct count in
		# manual mode; in automatic mode it will be set correctly inside
		# compute_timecodes()
		TIMECODES=( "${INITIAL_STAMPS[@]}" )
	else
		TIMECODES=( "${INITIAL_STAMPS[@]}" )
		compute_timecodes $TIMECODE_FROM $INTERVAL $NUMCAPS || {
			return $?
		}
	fi

	local output=$(new_temp_file '-preview.png')

	# If the temporal vidcaps for mplayer already exist, abort
	if [[ $DECODER -eq $DEC_MPLAYER ]]; then
		for f_ in 1 2 3 4 5; do
			if [[ -f "0000000${f_}.png" ]]; then
				error "File 0000000${f_}.png exists and would be overwritten, move it out before running."
				return $EX_CANTCREAT
			fi
		done
	fi

	# Assert sanity of decoder
	assert_if '[[ $DVD_MODE -ne 0 ]]' 'is_defined ${CAPTURER}_dvd_capture'
	assert 'is_defined ${CAPTURER}_capture'

	TEMPSTUFF=( "${TEMPSTUFF[@]}" '00000005.png' )

	# Highlights
	local hlfile n=1 # hlfile Must be outside the if!
	if [[ $HLTIMECODES ]]; then
		local hlcapfile= pretty=
		local -a capfiles
		for stamp in $(clean_timestamps "${HLTIMECODES[*]}"); do
			if fptest $stamp -gt ${VID[$LEN]} ; then (( ++n )) && continue ; fi
			pretty=$(pretty_stamp $stamp)
			inf "Generating highlight #${n}/${#HLTIMECODES[@]} ($pretty)..."
			hlcapfile=$(new_temp_file "-hl-$(pad 6 $n).png")

			capture "$f" "$hlcapfile" $stamp '1' || return $?
			[[ $CAPTURED_FROM_CACHE -eq 1 ]] ||\
			 filter_vidcap "$hlcapfile" $pretty $vidcap_width $vidcap_height $CTX_HL $n || {
				local r=$?
				error "Failed to apply transformations to the capture."
				return $r
			}
	
			capfiles=( "${capfiles[@]}" "$hlcapfile" )
			(( ++n ))
		done

		assert "[[ '"$n"' -gt 1 ]]"
		(( n-- )) # There's an extra inc
		if [[ $n -lt $NUM_COLUMNS ]]; then
			numcols=$n
		else
			numcols=$NUM_COLUMNS
		fi

		inf "Composing highlights contact sheet..."
		hlfile=$( create_contact_sheet $numcols $CTX_HL $vidcap_width $vidcap_height "${capfiles[@]}" )
		unset hlcapfile pretty n capfiles numcols
	fi
	unset n

	# Normal captures
	local capfile pretty n=1
	unset capfiles ; local -a capfiles ; local tfile=
	for stamp in $(clean_timestamps "${TIMECODES[*]}"); do
		pretty=$(pretty_stamp $stamp)
		inf "Generating capture #${n}/${#TIMECODES[*]} ($pretty)..."
		# identified by capture number, padded to 6 characters
		tfile=$(new_temp_file "-cap-$(pad 6 $n).png")

		capture "$f" "$tfile" $stamp $DISABLE_EVASION || {
			exitcode=$?
			[[ ${#capfiles[@]} -gt 0 ]] || {
				# No successful capture, unsupported format?
				# TODO: Adapt to capturer in use
				warn "No successful capture, possible unsupported format."
			}
			return $exitcode
		}
		if [[ $RESULT != "$stamp" ]]; then
			stamp=$RESULT
			pretty=$(pretty_stamp $RESULT)
		fi
		[[ $CAPTURED_FROM_CACHE -eq 1 ]] ||\
		 filter_vidcap "$tfile" $pretty $vidcap_width $vidcap_height $CTX_STD $n || return $?

		capfiles=( "${capfiles[@]}" "$tfile" )
		(( n++ ))
	done
	#filter_all_vidcaps "${capfiles[@]}"

	assert "[[ '"$n"' -gt 1 ]]"
	(( n-- )) # there's an extra inc
	if [[ $n -lt $NUM_COLUMNS ]]; then
		numcols=$n
	else
		numcols=$NUM_COLUMNS
	fi

	inf "Composing standard contact sheet..."
	output=$(create_contact_sheet $numcols $CTX_STD $vidcap_width $vidcap_height "${capfiles[@]}")
	unset capfile capfiles pretty n # must carry on to the extended caps: numcols

	# Extended mode
	local extoutput=
	if [[ $EXTENDED_FACTOR != 0 ]]; then
		# Number of captures. Always rounded to a multiplier of *double* the
		# number of columns (the extended caps are half width, this way they
		# match approx with the standard caps width)
		local hlnc=$(rtomult $(awkex "int(${#TIMECODES[@]} * $EXTENDED_FACTOR)") $((2*numcols)))

		unset TIMECODES # required step to get the right count
		declare -a TIMECODES # Note the manual stamps are not included anymore
		compute_timecodes $TC_NUMCAPS "" $hlnc
		unset hlnc

		local n=1 w= h= capfile= pretty=
		unset capfiles ; local -a capfiles
		# The image size of the extra captures is 1/4, adjusted to compensante the padding
		(( w=vidcap_width/2-PADDING, h=vidcap_height*w/vidcap_width ,1 ))
		assert "[[ ( '"$w"' -gt 0 ) && ( '"$h"' -gt 0 ) ]]"
		for stamp in $(clean_timestamps "${TIMECODES[*]}"); do
			pretty=$(pretty_stamp $stamp)
			capfile=$(new_temp_file "-excap-$(pad 6 $n).png")
			inf "Generating capture from extended set: ${n}/${#TIMECODES[*]} ($pretty)..."
			capture "$f" "$capfile" $stamp $DISABLE_EVASION || return $?
			[[ $CAPTURED_FROM_CACHE -eq 1 ]] ||\
			 filter_vidcap "$capfile" $pretty $w $h $CTX_EXT $n || return $?

			capfiles=( "${capfiles[@]}" "$capfile" )
			(( n++ ))
		done

		(( n-- )) # There's an extra inc
		if [[ $n -lt 'NUM_COLUMNS*2' ]]; then
			numcols=$n
		else
			numcols=$(( $NUM_COLUMNS * 2 ))
		fi

		inf "Composing extended contact sheet..."
		extoutput=$( create_contact_sheet $numcols $CTX_EXT $w $h "${capfiles[@]}" )

		unset w h capfile pretty n numcols
	fi # Extended mode

	local vcodec=${VID[$VCNAME]}
	local acodec=${VID[$ACNAME]}

	if [[ ${VID[$CHANS]} ]] && is_number "${VID[$CHANS]}" && [[ ${VID[$CHANS]} -ne 2 ]]; then
		if [[ ${VID[$CHANS]} -eq 1 ]]; then
			acodec="$acodec (mono)"
		else
			acodec="$acodec (${VID[$CHANS]}ch)"
		fi
	fi

	local csw=$(imw "$output") exw= hlw=
	local width=$csw
	if [[ -n $HLTIMECODES || ( $EXTENDED_FACTOR != '0' ) ]]; then
		inf "Merging contact sheets..."
		if [[ -n $HLTIMECODES ]]; then
			local hlw=$(imw "$hlfile")
			if [[ $hlw -gt $width ]]; then width=$hlw ; fi
		fi
		if [[ $EXTENDED_FACTOR != '0' ]]; then
			local exw=$(imw $extoutput)
			if [[ $exw -gt $width ]]; then width=$exw ; fi
		fi
	fi
	if [[ $csw -lt $width ]]; then
		local csh=$(imh "$output")
		# Expand the standard set to the maximum width of the sets by padding both sides
		# For some reason the more obvious (to me) convert command-lines lose
		# the transparency
		local csw2= ; (( csw2 = (width-csw) / 2 ))
		convert \( -size ${csw2}x$csh xc:transparent \) "$output" \
				\( -size ${csw2}x$csh xc:transparent \) +append "$output"
		unset csh csw2
	fi

	# If there were highlights then mix them in
	if [[ $HLTIMECODES ]]; then
		# For some reason adding the background also adds padding with:
		# convert \( -background LightGoldenRod "$hlfile" -flatten \) \
		# 	\( "$output" \) -append "$output"
		# replacing it with a "-composite" operation apparently works
		# Expand the highlights to the correct size by padding
		local hlh=$(imh "$hlfile")
		if [[ $hlw -lt $width ]]; then
			local hlw2= ; (( hlw2=(width - hlw) / 2 ))
			convert \( -size ${hlw2}x$hlh xc:transparent \) "$hlfile" \
					\( -size ${hlw2}x$hlh xc:transparent \) +append "$hlfile"
			unset hlw2
		fi
		convert \( -size ${width}x${hlh} xc:LightGoldenRod "$hlfile" -composite \) \
			\( -size ${width}x1 xc:black \) \
			"$output" -append "$output"
		unset hlh
	fi
	# Extended captures
	if [[ $EXTENDED_FACTOR != 0 ]]; then
		# Already set local exw=$(imw "$extoutput")
		local exh=$(imh "$extoutput")
		if [[ $exw -lt $width ]]; then
			# Expand the extended set to be the correct size
			local exw2= ; (( exw2=(width - exw) / 2 ))
			convert \( -size ${exw2}x$exh xc:transparent \) "$extoutput" \
					\( -size ${exw2}x$exh xc:transparent \) +append "$extoutput"
		fi
		convert "$output" -background Transparent "$extoutput" -append "$output"
	fi
	# Add the background; -trim added in 1.11. I'm unsure of why but whithout trimmin extra blank
	#+space is added at the top
	local dotrim=
	[[ ( $DISABLE_SHADOWS -eq 1 ) && ( -z $HLTIMECODES ) ]] && dotrim=-trim
	convert -background "$BG_CONTACT" "$output" -flatten $dotrim "$output"

	# Let's add meta inf and signature
	inf "Adding header and footer..."
	local meta2="Dimensions: ${VID[$W]}x${VID[$H]}"
	meta2="$meta2${NL}Format: $vcodec / $acodec${NL}FPS: ${VID[$FPS]}"
	local signature
	if [[ $ANONYMOUS_MODE -eq 0 ]]; then
		signature="$SIGNATURE $USERNAME${NL}with $PROGRAM_SIGNATURE"
	else
		signature="Created with $PROGRAM_SIGNATURE"
	fi
	local headwidth=$(imw "$output") headheight=
	local heading=$(new_temp_file .png)
	# Add the title if any
	if [[ $TITLE ]]; then
		local tlheight=$(line_height "$FONT_TITLE" "$PTS_TITLE")
		convert \
			\( \
				-size ${headwidth}x$tlheight "xc:$BG_TITLE" \
				-font "$FONT_TITLE" -pointsize "$PTS_TITLE" \
				-background "$BG_TITLE" -fill "$FG_TITLE" \
				-gravity Center -annotate 0 "$TITLE" \
			\) \
			-flatten \
			"$output" -append "$output"
		unset tlheight
	fi
	local fn_font=	# see $NONLATIN_FILENAMES
	if [[ $NONLATIN_FILENAMES -ne 1 ]]; then
		fn_font=$FONT_HEADING
	else
		fn_font=$NONLATIN_FONT
	fi
	# Create a small image to see how tall are characters. In my tests, no matter
	#+which character is used it's always the same height.
	local lineheight=$(line_height "$FONT_HEADING" "$PTS_META")
	# Since filename can be set in a different font check it too
	if [[ $fn_font != "$FONT_HEADING" ]]; then
		local fnlineheight=$(line_height "$fn_font" "$PTS_META")
		[[ $fnlineheight -le $lineheight ]] || lineheight=$fnlineheight
		unset fnlineheight
	fi
	headheight=$(( lineheight * 3 ))
	# Talk about voodoo... feel the power of IM... let's try to explain what's this:
	# It might technically be wrong but it seems to work as I think it should
	# (hence the voodoo I was talking)
	# Parentheses restrict options inside them to only affect what's inside too
	# * Create a base canvas of the desired width and height 1. The width is tweaked
	#   because using "label:" later makes the text too close to the border, that
	#   will be compensated in the last step.
	# * Create independent intermediate images with each row of information, the
	#   filename row is split in two images to allow changing the font, and then
	#   they're horizontally appended (and the font reset)
	# * All rows are vertically appended and cropped to regain the width in case
	#   the filename is too long
	# * The appended rows are appended to the original canvas, the resulting image
	#   contains the left row of information with the full heading width and
	#   height, and this is the *new base canvas*
	# * Draw over the new canvas the right row with annotate in one
	#   operation, the offset compensates for the extra pixel from the original
	#   base canvas. XXX: Using -annotate allows setting alignment but it breaks
	#   vertical alignment with the other rows' labels.
	# * Finally add the border that was missing from the initial width, we have
	#   now the *complete header*
	# * Add the contact sheet and append it to what we had.
	# * Start a new image and annotate it with the signature, then append it too.
	local filename_label="Filename"
	local filesize_label="File size"
	local filename_value=
	local filesize_value=
	if [[ $DVD_MODE -eq 1 ]]; then
		# lsdvd is guaranteed to be installed if DVD mode is enabled
		local dvd_label=$(lsdvd "$f" 2>/dev/null | grep -o 'Disc Title: .*' | cut -d' ' -f3-)
		# There's no guarantee that titles are on separate VTS, I have no idea
		# how to compute the actual title size
		if [[ $DVD_MOUNTP ]]; then
			filename_label="Disc label"
			filename_value="$dvd_label"
			filesize_label="Titleset size"
			filesize_value="$(get_dvd_size)"
		else
			# Not mounted. We can get the disc size but this will include any other titles.
			# Since 1.11 mounting DVDs is mandatory to get the title size. Both for ISOs and
			#+ devices
			filename_value="$(basename "$f") $filename_value (DVD Label: $dvd_label)"
			is_linux && warn "DVD not mounted: Can't detect title file size."
			filesize_label='Disc image size'
			filesize_value="$(get_pretty_size $(dur "$f"))"
		fi
	else
		filename_value="$(basename "$f")"
		filesize_value="$(get_pretty_file_size "$f")"
	fi

	local signlh=$(line_height "$FONT_SIGN" "$PTS_SIGN")
	local signheight=$(( 4 + ( signlh * 2 ) ))
	convert \
		\( \
			-size $(( headwidth - 18 ))x1 "xc:$BG_HEADING" +size \
			-font "$FONT_HEADING" -pointsize "$PTS_META" \
			-background "$BG_HEADING" -fill "$FG_HEADING" \
			\( \
				-gravity West \
				\( label:"$filename_label: " \
					-font "$fn_font" label:"$filename_value" +append \
				\) \
				-font "$FONT_HEADING" \
				label:"$filesize_label: $filesize_value" \
				label:"Length: $(cut -d'.' -f1 <<<$(pretty_stamp ${VID[$LEN]}))" \
				-append -crop ${headwidth}x${headheight}+0+0 \
			\) \
			-append \
			\( \
				-size ${headwidth}x${headheight} \
				-gravity NorthEast -fill "$FG_HEADING" -annotate +0-1 "$meta2" \
			\) \
			-bordercolor "$BG_HEADING" -border 9 \
		\) \
		"$output" -append \
		\( \
			-size ${headwidth}x$signheight -gravity Center "xc:$BG_SIGN" \
			-font "$FONT_SIGN" -pointsize "$PTS_SIGN" \
			-fill "$FG_SIGN" -annotate 0 "$signature" \
		\) \
		-append \
		"$output"
	unset signature meta2 headwidth headheight heading fn_font signheight signlh

	local wanted_name=${OUTPUT_FILES[$FILEIDX]}
	if [[ -n $wanted_name ]]; then
		local ERE='\.[^.]+$'
		if [[ $wanted_name =~ $ERE ]]; then
			FORMAT=$(filext "$wanted_name")
			inf "Output format set from output filename"
		else # No file extension in wanted_name
			wanted_name="$wanted_name.$FORMAT"
		fi
	fi
	[[ -n $wanted_name ]] || wanted_name="$(basename "$f").$FORMAT"

	if [[ $FORMAT != 'png' ]]; then
		local newout="$(dirname "$output")/$(basename "$output" .png).$FORMAT"
		convert -quality $QUALITY "$output" "$newout"
		output="$newout"
	fi

	output_name=$( safe_rename "$output" "$wanted_name" ) || {
		error "Failed to write the output file!"
		return $EX_CANTCREAT
	}
	inf "Done. Output wrote to $output_name"

	(( FILEIDX++ ,1 )) #,1 so that it's always ok
	if [[ $UNDFLAG_DISPLAY -eq 1 ]]; then
		if type -pf $UNDFLAG_DISPLAY_COMMAND; then
			$UNDFLAG_DISPLAY_COMMAND "$output_name"
		else
			display "$output_name"
		fi
	fi >/dev/null 2>&1
	[[ $UNDFLAG_DISCARD -eq 1 ]] && TEMPSTUFF+=( "$output_name" )
	[[ $UNDFLAG_HANG ]] && read -p 'Main loop paused, hit Enter key to continue... '
	cleanup

	# Re-set variables (for multi-file input)
	QUIRKS=$pre_quirks
	ASPECT_RATIO=$pre_aspect_ratio
	FORMAT="$pre_format"
}

# }}} # Core functionality

# {{{ # Debugging helpers

# Tests integrity of some operations.
# Used to test internal changes for consistency.
# It helps me to identify incorrect optimizations.
# internal_integrity_test(). Running with -D triggers this.
internal_integrity_test() {
	local t op val ret comm retval=0

	# Replacements
	local SEQ=$(type -pf seq)
	local JOT=$(type -pf jot)
	local ex rex
	if [[ $SEQ ]]; then
		ex=$($SEQ 1 10)
	elif [[ $JOT ]]; then
		ex=$($JOT 10 1)
	else
		warn "Can't check seqr() correctness, neither seq nor jot found"
	fi
	if [[ $ex ]]; then
		exr=$(seqr 1 10)
		if [[ $exr != "$ex" ]]; then
			error "Failed test: seqr() not consistent with external result"
			(( retval++ ,1 ))
		else
			inf "Passed test (seq replacement): consistent result"
		fi
	fi

	# Textual tests, compare output to expected output
	# Tests are in the form "operation arguments correct_result #Description"
	TESTS=( # Note bash2 doesn't like this array as a local variable
		# TODO: UNIX vs GNU
		#"stonl ..."

		"rmultiply 1,1 1 #Identity"
		"rmultiply 16/9,1 2 #Rounding" # 1.77 rounded 2
		"rmultiply 4/3 1 #Rounding"    # 1.33 rounded 1
		"rmultiply 1,16/9 2 #Commutative property"
		"rmultiply 1.7 2 #Alternate syntax"

		"ceilmultiply 1,1 1 #"
		"ceilmultiply 4/3 2 #" # 1.33 rounded 2
		"ceilmultiply 7,1/2 4 #" # 3.5 rounded 4
		"ceilmultiply 7/2 4 #Alternative syntax"
		"ceilmultiply 1/2,7 4 #Commutative property"

		"pad 10 0 0000000000 #Padding"
		"pad 1 20 20 #Unneeded padding"
		"pad 5 23.3 023.3 #Floating point padding"

		"guess_aspect 720 576 4/3 #DVD AR Guess"
		"guess_aspect 1024 576 1024/576 #Unsupported Wide AR Guess"

		"tolower ABC abc #lowercase conversion"

		"pyth_th 4 3 5 #Integer pythagorean theorem"
		#bc result: "pyth_th 16 9 18.35755975068581929849 #FP pythagorean theorem"
		#perl result: "pyth_th 16 9 18.3575597506858 #FP pythagorean theorem"
		"pyth_th 16 9 18.35755975068581946630 #FP pythagorean theorem"

		"get_interval 2h 7200 #Hours parsing"
		"get_interval 2m 120 #Minutes parsing"
		"get_interval 30S 30 #Seconds parsing"
		"get_interval .30 .30 #Milliseconds parsing"
		# Since now the numbers are passed to perl, leading zeroes become octal
		# numbers. Must ensure they are handled correctly
		"get_interval 09h010m09s1 33010 #Parsing with leading zeroes"
		"get_interval 0400 400 #Parsing shorthand"
		# Extended syntax
		"get_interval 30m30m1h 7200 #Repeated minutes parsing"

		# File size rounding
		"get_pretty_size 1127428915 1.05%20GiB #Leading zeroes in file size (GiB)"
		"get_pretty_size 1132462 1.08%20MiB #Leading zeroes in file size (MiB)"
		"get_pretty_size 1116 1.09%20KiB #Leading zeroes in file size (KiB)"
		"get_pretty_size 1889785610 1.76%20GiB #Pretty-printed file size (GiB)"
		"get_pretty_size 762650296 727.32%20MiB #Pretty-printed file size (MiB)"
		"get_pretty_size 524810 512.51%20KiB #Pretty-printed file size (KiB)"
	)
	
	for t in "${TESTS[@]}" ; do
		comm=${t/#*#/} # 's/.*#//'
		t=${t/%#*/}    # 's/#.*//'
		# Expected value
		val=$(awk '{print $NF}' <<<$t)
		op=$(sed "s! $val *\$!!" <<<$t) # Don't use delimiter '/', passed in some $val
		val=${val/\%20/ }
		[[ -n $comm ]] || comm=unnamed
		ret=$($op) || true

		if [[ $ret != "$val" ]] && fptest "$ret" -ne "$val" ; then
			error "Failed test ($comm): '$op $val'. Expected '$val'. Got '$ret'."
			(( ++retval ))
		else
			inf "Passed test ($comm): '$op $val'."
		fi
	done

	# Returned value tests, compare return to expected return
	TESTS=(
		# Don't use anything with a RE meaning

		# Floating point numeric "test"
		"fptest 3 -eq 3 0 #FP test" 
		"fptest 3.2 -gt 1 0 #FP test"
		"fptest 1/2 -le 2/3 0 #FP test"
		"fptest 6.34 -gt 6.34 1 #FP test"
		"fptest (1>0) -eq 1 0 #FP -logical- test"

		"is_number 3 0 #Numeric recognition"
		"is_number '3' 1 #Quoted numeric recognition"
		"is_number 3.3 1 #Non-numeric recognition"

		"is_float 3.33 0 #Float recognition"
		"is_float 3 0 #Float recognition"
		"is_float 1/3 1 #Non-float recognition"

		"is_fraction 1/1 0 #Fraction recognition"
		"is_fraction 1 1 #Non-fraction recognition"
		"is_fraction 1.1 1 #Non-fraction recognition"

		"is_pos_or_percent 33 0 #Positive recognition"
		"is_pos_or_percent 33% 0 #Percent recognition"
		"is_pos_or_percent 4/4% 1 #Percent recognition"
		"is_pos_or_percent % 1 #Percent recognition"
	)
	for t in "${TESTS[@]}"; do
		comm=${t/#*#/} # 's/.*#//'
		t=${t/%#*/}    # 's/#.*//'
		val=$(awk '{print $NF}' <<<$t)
		op=$(sed "s! $val *\$!!" <<<$t)
		[[ -n $comm ]] || comm=unnamed
		ret=0
		$op || {
			ret=$?
		}

		if [[ $val -eq $ret ]]; then
			inf "Passed test ($comm): '$op; returns $val'."
		else
			error "Failed test ($comm): '$op; returns $val'. Returned '$ret'"
			(( retval++ ,1 ))
		fi
	done

	return $retval
}


# }}} # Debugging helpers

# {{{ # Help / Info

# Prints the program identification to stderr
show_vcs_info() { # Won't be printed in quiet modes
	# Don't colourise this
	infplain "Video Contact Sheet *NIX v${VERSION}${SUBVERSION}, (c) 2007-2019 Toni Corvera"
}

# Prints the list of options to stdout
# show_help($1 = long = '')
show_help() {
	local P=$(basename $0)
	local showlong=$1
	local mpchosen= ffchosen= longhelp= funkyex=
	[[ -z $MPLAYER_BIN ]] && mpchosen=' [Not available]'
	[[ $MPLAYER_BIN && ( $DECODER == $DEC_MPLAYER ) ]] && mpchosen=' [Selected]'
	[[ -z $FFMPEG_BIN ]] && ffchosen=', Not available'
	[[ $FFMPEG_BIN && ( $DECODER == $DEC_FFMPEG ) ]] && ffchosen=', Selected'
	# This portion of help is only shown when in full help mode (--fullhelp)
	[[ $showlong ]] && longhelp=\
"  --anonymous           Disable the 'Preview created by' line in the footer.
  -Ij|-Ik|-Ij=fontname|-Ik=fontname
  --nonlatin            Use an alternate font in the heading for the video file
                        name. Required to display correctly file names in
                        some languages (Chinese, Japanese, Hangul,
                        Cyrillic, ...).
                        Will try to use a reasonable font. Can also be set
                        manually like:
                        $ vcs -Ij=Sazanami-Mincho-Regular file.avi
                        or
                        $ vcs -Ij=/usr/share/fonts/ttf/ttf-japanese-mincho.ttf\\
                               file.avi
                        Use \"identify -list font\" to list the available fonts
  -O|--override <arg>   Override a variable (see the homepage for more details).
                        The accepted format is 'variable=value' (can
                        also be quoted -variable=\"some value\"- and can take an
                        internal variable too -variable='\$SOME_VAR'-).

  Tweaks and workarounds:
  -Ws                   Increase length of safe measuring (try harder). Repeat
                        to increase further.
  -WS                   Scan all video, if required, to get a safe measuring.
  -Wp                   Increase safe measuring precission (i.e. halve the
                        probe stepping). Repeat to increase further.
  -WP                   Inverse of -Wp.
  -Wo                   Change ffmpeg's arguments order, might work with some
                        files that fail otherwise.
  -Wc                   Disable colour in console messages.
                        NOTE: If you have any configuration loaded before this
                             takes effect the script might still print some
                             colour. You can disable it completely by setting
                             the TERM variable to a monochrome term type, e.g.:
                             $ env TERM=vt100 vcs [options]
  Obscure options, debugging tools and workarounds:
  -R <file>
  --randomsource <file> Use the provided file as a source for \"random\" values:
                        they won't be random anymore, so two runs with the same
                        source and same arguments will produce the same output
                        in modes which use randomisation (e.g. the
                        \"photos\" and \"polaroid\" modes).
  -D                    Debug mode. Used to test features/integrity. It:
                          * Prints the input command line
                          * Sets the title to reflect the command line
                          * Does a basic test of consistency
                          * Prints all internal functions as they are called
"
	# The --funky help is really long, so make it shorter by default,
        # only show the complete help when --fullhelp is used
	[[ $showlong ]] && funkyex="
                        These are toy output modes in which the contact sheet
                        gets a more informal look.
                        Order *IS IMPORTANT*. A bad order gets a bad result :P
                        Many of these modes are random in nature so using the
                        same mode twice will usually lead to different results.
                        Currently available \"funky modes\":
                        \"overlap\":  Use '-ko' or '--funky overlap'
                            Randomly overlap captures.
                        \"rotate\":     Use '-kr' or '--funky rotate'
                            Randomly rotate each image.
                        \"photoframe\": Use '-kf' or '--funky photoframe'
                            Adds a photo-like white frame to each image.
                        \"polaroidframe\": Use '-kL' or '--funky polaroidframe'
                            Adds a polaroid picture-like white frame to each
                            image.
                        \"photos\": Use '-kc' or '--funky photos'
                            Combination of rotate, photoframe and overlap.
                            Same as -kp -kr -ko.
                        \"polaroid\": Use '-kp' or '--funky polaroid'
                            Combination of rotate, polaroidframe and overlap.
                            Same as -kL -kr -ko.
                        \"film\":     Use '-ki' or '--funky film'
                            Imitates filmstrip look.
                        \"random\":   Use '-kx' or '--funky random'
                            Randomises colours and fonts."
	[[ -z $showlong ]] && funkyex="
                        Available: overlap, rotate, photoframe, polaroidframe,
                                   photos, polaroid, film, random
                        Use --fullhelp for more details."
	cat <<EOF
Usage: $P [options] <file>

Options:
  -i|--interval <arg>   Set the interval to arg. Units can be used
                        (case-insensitive), i.e.:
                            Seconds:      90 or 90s
                            Minutes:      3m
                            Hours:        1h
                            Combined:     1h3m90
                        Use either -i or -n.
  -n|--numcaps <arg>    Set the number of captured images to arg. Use either
                        -i or -n.
  -c|--columns <arg>    Arrange the output in 'arg' columns.
  -H|--height <arg>     Set the output (individual thumbnail) height. Width is
                        derived accordingly. Note width cannot be manually set.
  -o|--output <file>    File name of output. When ommited will be derived from
                        the input filename. Can be repeated for multiple files.
  -a|--aspect <aspect>  Aspect ratio. Accepts a floating point number or a
                        fraction.
  -f|--from <arg>       Set starting time. No caps before this. Same format
                        as -i.
  -t|--to <arg>         Set ending time. No caps beyond this. Same format
                        as -i.
  -T|--title <arg>      Add a title above the vidcaps.
  -j|--jpeg             Output in jpeg (by default output is in png).
  -j2|--jpeg2           Output in jpeg 2000
  -V|--dvd              DVD Mode.
                        In this mode the input <file>s must be the DVD
                        device(s) or ISO(s). When in DVD mode all input files
                        must be DVDs.
                        Implies -A (auto aspect ratio)
  --dvd-title <arg>     DVD title to use. Using 0 (the default) will use the
                        longest title.
  -M|--mplayer          Use Mplayer to capture$mpchosen
  -F|--ffmpeg           Use FFmpeg to capture [Default$ffchosen]
  -E|--end-offset <arg> This amount of time is ignored from the end of the
                        video.
                        Accepts timestamps (same format as -i) and percentages.
                        This value is not used when a explicit ending time is
                        set.
                        The default is $DEFAULT_END_OFFSET.
  -q|--quiet            Don't print progress messages just errors. Repeat to
                        mute completely, even on error.
  -h|--help             Show basic help and exit.
  --fullhelp            Show the complete help and exit.
  -d|--disable <arg>    Disable some default functionality.
                        Features that can be disabled are:
                        * timestamps: use -dt or --disable timestamps
                        * shadows: use -ds or --disable shadows
                        * padding: use -dp or --disable padding
                          (note shadows introduce some extra padding)
  -A|--autoaspect       Try to guess aspect ratio from resolution.
  -e[num] | --extended=[num]
                        Enables extended mode and optionally sets the extended
                        factor. -e is the same as -e$DEFAULT_EXT_FACTOR.
  -l|--highlight <arg>  Add the frame found at timestamp "arg" as a
                        highlight. Same format as -i.
  -m|--manual           Manual mode: Only timestamps indicated by the user are
                        used (use in conjunction with -S), when using this
                        -i and -n are ignored.
  -S|--stamp <arg>      Add the frame at timestamp "arg" to the set of captures.
                        Same format as -i.

  -u|--user <arg>       Set the username (included by default in the sheet's
                        footer) to this value.
  -U|--fullname         Use user's full/real name (e.g. John Smith) as found
                        set in the system's list of users.
  -p|--profile <arg>    Load profile "arg"
  -C|--config <arg>     Load configuration file "arg"
  --generate <config|profile>
                        Generate configuration or profile from current settings
  -k <arg>
  --funky <arg>         Funky modes:$funkyex
$longhelp
Examples:
    Create a contact sheet with default values (vidcaps at intervals of
    $DEFAULT_INTERVAL seconds), will be saved to 'video.avi.png':
        \$ $P video.avi

    Create a sheet with vidcaps at intervals of 3 and a half minutes, save to
    'output.jpg':
        \$ $P -i 3m30 input.wmv -o output.jpg

    Create a sheet with vidcaps starting at 3 mins and ending at 18 mins,
    add an extra vidcap at 2m and another one at 19m:
        \$ $P -f 3m -t 18m -S2m -S 19m input.avi

    See more examples at vcs' homepage <http://p.outlyer.net/vcs/>.

EOF
	# ' # Syntax highlighting bait
}

# Print a configuration file generated from the currently active settings
# generate_config($1 = <config|profile>)
generate_config() {
	local n=$(echo $1 | tr a-z A-Z) f= t= x=
	cat <<-EOM
	# --- $n STARTS HERE ---
	# This is a sample configuration file for VCS generated automatically
	# from the command-line with the "--generate $1" command-line option
	# Save it to ~/.vcs.conf or ~/.vcs/vcs.conf to make it the default
	# configuration.
	# OR
	# Save it to ~/.vcs/profiles/something.conf to create a profile named
	# "something". To use this profile run vcs with the "--profile something"
	# (or "-p something") option
	# OR
	# Save it to "something.conf" and load it with "--config something.conf"
	# (or "-C something.conf")
EOM
	echo "${OVERRIDE_MAP[*]}" | stonl | egrep -v '(deprecated=|alias)' | cut -d':' -f1-2 |\
	 while read ovname ; do
		f=${ovname/:*}
		t=${ovname#*:}
		if [[ ( -z $t ) || ( $t == '=' ) ]]; then t=$f ; fi
		eval v=\$USR_$t
		[[ -z $v ]] || {
			# Symbolic values:
			case $( tolower "$t" ) in
				timecode_from)
					x='$TC_NUMCAPS'
					[[ $v -eq $TC_NUMCAPS ]] || x='$TC_INTERVAL'
					v=$x
					;;
				decoder)
					x='$DEC_FFMPEG'
					[[ $v -eq $DEC_FFMPEG ]] || x='$DEC_MPLAYER'
					v=$x
					;;
				verbosity)
					case $v in
						$V_ALL) v='$V_ALL' ;;
						$V_NONE) v='$V_NONE' ;;
						$V_INFO) v='$V_INFO' ;;
						$V_WARN) v='$V_WARN' ;;
						$V_ERROR) v='$V_ERROR' ;;
					esac # verbosity
					;;
			esac
			[[ -z $v ]] || {
				# Don't print unnecessary decimals
				if [[ $v =~ ^[0-9][0-9]*\.[0-9][0-9]*$ ]]; then
					v=$(sed -e 's/0*$//' -e 's/\.$//' <<<"$v")
				fi
			}
			# Print all names in lowercase
			echo "$(tolower "$f")=$v"
		}
	done
	echo "# vcs:conf:$NL# Generated on $(date)$NL# --- $n ENDS HERE --- "
	exit 0
}

# }}} # Help / Info

#### Entry point ####

# Important to do this before any message can be thrown
init_feedback

# Ensure $GETOPT is GNU/Linux-style getopt
choose_getopt

# Execute exithdlr on exit
trap exithdlr EXIT

show_vcs_info

# Test requirements. Important, must check before looking at the
# command line (since getopt is used for the task)
test_programs

# The command-line overrides any configuration. And the configuration
# is able to change the program in charge of parsing options ($GETOPT)
load_config

# {{{ # Command line parsing

# TODO: Find how to do this correctly (this way the quoting of $@ gets messed):
#eval set -- "${default_options} ${@}"
ARGS="$@"

# [[R0]]
# TODO: Why does FreeBSD's GNU getopt ignore -n??
TEMP=$("$GETOPT" -n "$0" -s bash \
	-o i:n:u:T:f:t:S:j::hFMH:c:ma:l:De::U::qAO:I:k:W:E:d:VR:Z:o:p:C: \
       --long "interval:,numcaps:,username:,title:,from:,to:,stamp:,jpeg::,help,"\
"mplayer,ffmpeg,height:,columns:,manual,aspect:,highlight:"\
"extended::,fullname,anonymous,quiet,autoaspect,override:,mincho,funky:,"\
"end_offset:,end-offset:,disable:,dvd,dvd-title:,randomsource:,undocumented:,output:,"\
"fullhelp,profile:,"\
"jpeg2,nonlatin,generate:,config:" \
       -- "$@")
eval set -- "$TEMP"

while true ; do
	case $1 in
		-i|--interval)
			check_constraint 'interval' "$2" "$1" || die
			INTERVAL=$(get_interval $2)
			TIMECODE_FROM=$TC_INTERVAL
			USR_INTERVAL=$INTERVAL
			USR_TIMECODE_FROM=$TC_INTERVAL
			shift # Option arg
			;;
		-n|--numcaps)
			check_constraint 'numcaps' "$2" "$1" || die
			NUMCAPS=$2
			TIMECODE_FROM=$TC_NUMCAPS
			USR_NUMCAPS=$2
			USR_TIMECODE_FROM=$TC_NUMCAPS
			shift # Option arg
			;;
		-o|--output)
			current=${#OUTPUT_FILES[@]}
			OUTPUT_FILES[$current]=$2
			shift ;;
		-u|--username) USERNAME=$2 ; USR_USERNAME=$USERNAME ; shift ;;
		-U|--fullname)
			# -U accepts an optional argument, 0, to make an anonymous signature
			# --fullname accepts no argument
			if [[ $1 == '-U' ]]; then # -U always provides an argument
				if [[ -n $2 ]]; then # With argument, special handling
					if [[ $2 != '0' ]]; then
						error "Use '-U0' to make an anonymous contact sheet or '-u \"My Name\"'"
						error "    to sign as My Name. Got -U$2"
						exit $EX_USAGE
					fi
					ANONYMOUS_MODE=1
					USR_ANONYMOUS_MODE=1
				fi
				shift
			else # No argument, default handling (try to guess real name)
				idname=$(id -un)
				if type -p getent >/dev/null ; then
					USERNAME=$(getent passwd "$idname" | cut -d':' -f5 | sed 's/,.*//g')
				else
					USERNAME=$(grep "^$idname:" /etc/passwd | cut -d':' -f5 | sed 's/,.*//g')
				fi
				if [[ -z $user ]]; then
					USERNAME=$idname
					error "No fullname found, falling back to default ($USERNAME)"
				fi
				unset idname
			fi
			;;
		--anonymous) ANONYMOUS_MODE=1 ; USR_ANONYMOUS_MODE=1 ;; # Same as -U0
		-T|--title) TITLE="$2" ; USR_TITLE="$2" ; shift ;;
		-f|--from)
			if ! FROMTIME=$(get_interval "$2") ; then
				error "Starting timestamp must be a valid timecode. Got '$2'."
				exit $EX_USAGE
			fi
			USR_FROMTIME="$FROMTIME"
			shift
			;;
		-E|--end_offset|--end-offset)
			if [[ $1 == '--end_offset' ]]; then
				warn "Option --end_offset is deprecated and will be removed in the"
				warn " next version, please use --end-offset instead"
			fi
			check_constraint 'end_offset' "$2" "$1" || die
			is_p='y'
			is_percentage "$2" || is_p=''
			if [[ $is_p ]]; then
				END_OFFSET="$2"
			else
				END_OFFSET=$(get_interval "$2")
			fi
			USR_END_OFFSET="$END_OFFSET"
			unset is_i
			shift
			;;
		-t|--to)
			if ! TOTIME=$(get_interval "$2") ; then
				error "Ending timestamp must be a valid timecode. Got '$2'."
				exit $EX_USAGE
			fi
			if fptest "$TOTIME" -eq 0 ; then
				error "Ending timestamp was set to 0, set to movie length."
				totime=-1
			fi
			USR_TOTIME=$TOTIME
			shift
			;;
		-S|--stamp)
			if ! temp=$(get_interval "$2") ; then
				error "Timestamps must be a valid timecode. Got '$2'."
				exit $EX_USAGE
			fi
			INITIAL_STAMPS=( "${INITIAL_STAMPS[@]}" "$temp" )
			shift
			;;
		-l|--highlight)
			if ! temp=$(get_interval "$2"); then
				error "Timestamps must be a valid timecode. Got '$2'."
				exit $EX_USAGE
			fi
			HLTIMECODES=( "${HLTIMECODES[@]}" "$temp" )
			shift
			;;
		--jpeg2) # Note --jpeg 2 is also accepted
			FORMAT=jp2
			USR_FORMAT=jp2
			;;
		-j|--jpeg)
			if [[ $2 ]]; then # Arg is optional, 2 is for JPEG 2000
				# 2000 is also accepted
				if [[ $2 != '2' && $2 != '2000' ]]; then
					error "Use -j for jpeg output or -j2 for JPEG 2000 output. Got '-j$2'."
					exit $EX_USAGE
				fi
				FORMAT=jp2
			else
				FORMAT=jpg
			fi
			USR_FORMAT="$FORMAT"
			shift
			;;
		-h|--help) show_help ; exit $EX_OK ;;
		--fullhelp) show_help 'full' ; exit $EX_OK ;;
		-F|--ffmpeg) set_capturer ffmpeg ;;
		-M|--mplayer) set_capturer mplayer ;;
		-H|--height)
			check_constraint 'height' "$2" "$1" || die
			HEIGHT="$2"
			USR_HEIGHT="$2"
			shift
			;;
		-a|--aspect)
			if ! is_float "$2"  && ! is_fraction "$2" ; then
				error "Aspect ratio must be expressed as a (positive) floating "
				error "    point number or a fraction (ie: 1, 1.33, 4/3, 2.5). Got '$2'."
				exit $EX_USAGE
			fi
			ASPECT_RATIO="$2"
			USR_ASPECT_RATIO="$2"
			shift
			;;
		-A|--autoaspect) ASPECT_RATIO=-1 ; USR_ASPECT_RATIO=-1 ;;
		-c|--columns)
			check_constraint 'columns' "$2" "$1" || die
			NUM_COLUMNS="$2"
			USR_NUM_COLUMNS="$2"
			shift
			;;
		-m|--manual) MANUAL_MODE=1 ;;
		-e|--extended)
			# Optional argument quirks: $2 is always present, set to '' if unused
			# from the commandline it MUST be directly after the -e (-e2 not -e 2)
			# the long format is --extended=VAL
			if [[ $2 ]]; then
				check_constraint 'extended_factor' "$2" "$1" || die
				EXTENDED_FACTOR="$2"
			else
				EXTENDED_FACTOR=$DEFAULT_EXT_FACTOR
			fi
			USR_EXTENDED_FACTOR=$EXTENDED_FACTOR
			shift
			;;
		# Unlike -I, --nonlatin does not accept a font name
		--nonlatin)
			if [[ -z $USR_NONLATIN_FONT ]]; then
				NONLATIN_FILENAMES=1
				USR_NONLATIN_FILENAMES=1
				set_extended_font
				inf "Filename font set to '$NONLATIN_FONT'"
			fi
			;;
		-I)
			# Extended/non-latin font
			# New syntax introduced in 1.11:
			# -Ij:  Try to pick automatically a CJK font. Might fail and abort
			# -Ij='Font name or file': Set font manually
			#
			# If an argument is passed, test it is one of the known ones
			case $2 in
				k|j|k=*|j=*) ;;
				*) error "-I must be followed by j or k!" && exit $EX_USAGE ;;
			esac
			# It isn't tested for existence because it could also be a font
			# which convert would understand without giving the full path
			NONLATIN_FILENAMES=1
			USR_NONLATIN_FILENAMES=1
			if [[ ${#2} -gt 1 ]]; then
				# j=, k= syntax
				NONLATIN_FONT="${2:2}"
				USR_NONLATIN_FONT="$NONLATIN_FONT"
				inf "Filename font set to '$NONLATIN_FONT'"
			fi
			# If the user didn't pick one, try to select automatically
			if [[ -z $USR_NONLATIN_FONT ]]; then
				set_extended_font
				inf "Filename font set to '$NONLATIN_FONT'"
			fi
			shift
			;;
		-O|--override)
			# Rough test
			RE='[a-zA-Z_]+=[^;]*'
			if [[ ! $2 =~ $RE ]]; then
				error "Wrong override format, it should be variable=value. Got '$2'."
				exit $EX_USAGE
			fi
			two=$(tolower "$2")
			RE='^[[:space:]]*getopt='
			if [[ $two =~ $RE ]] ; then # getopt=
				# If we're here, getopt has already been found and works, so it makes no
				# sense to override it; on the other hand, if it hasn't been correctly
				# set/detected we won't reach here
				warn "Setting 'getopt' can't be overridden from the command line."
			else
				cmdline_override "$2"
				POST_GETOPT_HOOKS+=( 1:cmdline_overrides_flush )
			fi
			shift
			;;
		-W)
			case $2 in
				# (classic) Workaround mode. See wa_ss_* declarations at the start for details
				o) wa_ss_af='-ss ' ; wa_ss_be='' ;;
				# Console colout
				# Once: Disable console colour, use prefixes instead
				# Twice: Disable prefixes too
				c)
				  set_feedback_prefixes
				  [[ -n $UNDFLAG_NOPREFIX ]] && SIMPLE_FEEDBACK=1
				  UNDFLAG_NOPREFIX=1
				  ;;
				# Double length of video probed in safe measuring
				# Semi-undocumented traits:
				#  - Can be repeated, will double for each instance
				#  - -Ws -Ws -Ws = -Ws3
				s|s[0-9]|s[0-9][0-9])
				  [[ ${#2} -gt 1 ]] && n=${2:1} || n=1
				  QUIRKS_MAX_REWIND=$(awkexf "$QUIRKS_MAX_REWIND * (2^$n)")
				  (( INTERNAL_WS_C+=n ,1 ))
				  ;;
				# Brute force -Ws: Test all the length of the file if required
				S) QUIRKS_MAX_REWIND=-1 ;;
				# Increase precission of safe length measuring (halve the stepping)
				# Like -Ws can be repeated
				p|p[0-9]|p[0-9][0-9])
				  [[ ${#2} -gt 1 ]] && n=${2:1} || n=1
				  QUIRKS_LEN_STEP=$(awkexf "$QUIRKS_LEN_STEP / (2^$n)")
				  (( INTERNAL_WP_C+=n ,1 ))
				  ;;
				# Inverse of -Wp: Decrease precission of safe length measuring
				# i.e.: will try less times <-> will be quicker but less accurate
				# desirable when -Ws or -WS are used.
				# Can also be repeated
				P|P[0-9]|P[0-9][0-9])
				  [[ ${#2} -gt 1 ]] && n=${2:1} || n=1
				  QUIRKS_LEN_STEP=$(awkexf "$QUIRKS_LEN_STEP * (2^$n)")
				  (( INTERNAL_WP_C-=n ,1 ))
				  ;;
				# -Wb (Semi-undocumented): Disable safe mode. Use this to force accepting
				#+broken/partial files. Only makes sense when testing or in combination
				#+with stuff like '-Z idonly'
				b) QUIRKS=-2 ;; # Quirks < 0 : No safe mode
				*)
				  error "Wrong argument. Use --fullhelp for a list available workarounds. Got -W$2."
				  exit $EX_USAGE
				  ;;
			esac
			shift
			;;
		-k|--funky) # Funky modes
			case "$2" in # Note older versions (<1.0.99) were case-insensitive
				p|polaroid) # Same as overlap + rotate + polaroid
					inf "Polaroid mode enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_polaroid' 'filt_randrot' )
					CSHEET_DELEGATE='csheet_overlap'
					# XXX: The newer version has a lot less flexibility with these many
					# hardcoded values...
					GRAV_TIMESTAMP=South
					FG_TSTAMPS=Black
					BG_TSTAMPS=Transparent
					PTS_TSTAMPS=$(( $PTS_TSTAMPS * 3 / 2 ))
					;;
				c|photos) # Same as overlap + rotate + photoframe, this is the older polaroid
					inf "Photos mode enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_photoframe' 'filt_randrot' )
					CSHEET_DELEGATE='csheet_overlap'
					# The timestamp must change location to be visible most of the time
					GRAV_TIMESTAMP=NorthWest
					;;
				o|overlap) # Random overlap mode
					inf "Overlap mode enabled."
					CSHEET_DELEGATE='csheet_overlap'
					GRAV_TIMESTAMP=NorthWest
					;;
				r|rotate) # Random rotation
					inf "Random rotation of captures enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_randrot' )
					;;
				f|photoframe) # White photo frame
					inf "Photoframe mode enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_photoframe' )
					;;
				L|polaroidframe) # White polaroid frame
					inf "Polaroid frame mode enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_polaroid ')
					GRAV_TIMESTAMP=South
					FG_TSTAMPS=Black
					BG_TSTAMPS=Transparent
					PTS_TSTAMPS=$(( $PTS_TSTAMPS * 3 / 2 ))
					;;
				i|film)
					inf "Film mode enabled."
					FILTERS_IND=( "${FILTERS_IND[@]}" 'filt_film' )
					;;
				x|random) # Random colours/fonts
					inf "Fonts and colours randomisation enabled."
					randomize_look
					;;
				*)
					error "Unknown funky mode requested. Got '$2'."
					exit $EX_USAGE
					;;
			esac
			shift
			;;
		-p|--profile)
			case $2 in
			  classic) # Classic colour scheme
			    BG_HEADING=YellowGreen BG_SIGN=SlateGray BG_CONTACT=White
			    BG_TITLE=White FG_HEADING=Black FG_SIGN=Black
			    ;;
			  1.0) # 1.0a, 1.0.1a and 1.0.2b colourscheme
			    BG_HEADING=YellowGreen BG_SIGN=SandyBrown BG_CONTACT=White
			    BG_TITLE=White FG_HEADING=Black FG_SIGN=Black
			    ;;
			  *) load_profile "$2" || die
			    ;;
			esac
			shift
			;;
		-C|--config)
			if [[ $2 =~ ^: ]]; then
				if [[ $2 == ':pwd' ]]; then
					cfg=./vcs.conf
				else
					error "Configuration names starting with ':' are reserved."
					exit $EX_USAGE
				fi
			else
				cfg=$2
			fi
			[[ -f $cfg ]] || {
				error "Configuration file '$cfg' not found"
				exit $EX_USAGE
			}
			# ./vcs.conf doesn't need the vcs:conf: mark
			if [[ $2 != ':pwd' ]]; then
				head -5 "$cfg" | grep -q '#[[:space:]]*vcs:conf[[:space:]]*:' || \
				tail -5 "$cfg" | grep -q '#[[:space:]]*vcs:conf[[:space:]]*:' || {
					error "No vcs:conf: mark found in '$cfg'"
					exit $EX_NOINPUT
				}
			fi
			load_config_file "$cfg" 'Custom configuration'
			shift
			;;
		-R|--randomsource)
			if [[ ! -r $2 ]]; then
				error "Random source file '$2' can't be read"
				exit $EX_USAGE
			fi
			init_filerand "$2"
			inf "Using '$2' as source of semi-random values"
			RANDFUNCTION=filerand
			shift
			;;
		-d|--disable) # Disable default features
			case $(tolower "$2") in
				# timestamp (with no final s) is undocumented but will stay
				t|timestamps|timestamp)
					if [[ $DISABLE_TIMESTAMPS -eq 0 ]]; then
						inf "Timestamps disabled."
						# They'll be removed from the filter chain in coherence_check
						DISABLE_TIMESTAMPS=1
					fi
					;;
				s|shadows|shadow)
					if [[ $DISABLE_SHADOWS -eq 0 ]]; then
						inf "Shadows disabled."
						# They will be removed from the filter chain in coherence_check
						DISABLE_SHADOWS=1
					fi
					;;
				p|padding)
					if [[ $PADDING -ne 0 ]] ; then
						inf "Padding disabled." # Kinda...
						PADDING=0
					fi
					;;
				*)
					error "Requested disabling unknown feature. Got '$2'."
					exit $EX_USAGE
					;;
			esac
			shift
			;;
		--dvd-title)
			check_constraint 'dvd_title' "$2" "$1" || die
			DVD_TITLES=( "${DVD_TITLES[@]}" "$2" )
			shift
			;;
		-V|--dvd)
			# XXX; Are there systems with no perl???
			if ! type -pf perl >/dev/null ; then
				error "DVD support requires perl"
				exit $EX_UNAVAILABLE
			fi
			# DVD Mode requires lsdvd
			if ! type -pf lsdvd >/dev/null ; then
				error "DVD support requires the lsdvd program"
				exit $EX_UNAVAILABLE
			fi
			DVD_MODE=1
			ASPECT_RATIO=-2 # Special value: Auto detect only if ffmpeg couldn't
			;;
		-q|--quiet)
			# -q to only show errors
			# -qq to be completely quiet
			if [[ $VERBOSITY -gt $V_ERROR ]]; then
				VERBOSITY=$V_ERROR
			else
				VERBOSITY=$V_NONE
			fi
			USR_VERBOSITY=$VERBOSITY
			;;
		-Z|--undocumented)
			# This is a container for, of course, undocumented functions
			# These are used for testing/debugging purposes. Might (and will)
			# change between versions, break easily and do no safety checks.
			# In short, don't look at them unless told to do so :P
			case "$2" in
				# AWK was used for a little while in a WiP version
				#set_awk=*) AWK="$(cut -d'=' -f2<<<"$2")" ; warn "[U] AWK=$AWK" ;;
				# Hang the main process loop just before cleanup.
				hang) UNDFLAG_HANG="On" ; warn "[U] Hang flag" ;;
				# Print identification results, do nothing else
				idonly) UNDFLAG_IDONLY="On" ; warn "[U] Id only" ;;
				# ffmpeg path
				set_ffmpeg=*)
					FFMPEG_BIN=$(realpathr "$(cut -d'=' -f2<<<"$2")")
					assert '[[ -x $FFMPEG_BIN ]]'
					warn "[U] FFMPEG_BIN=$FFMPEG_BIN"
					;;
				# mplayer path
				set_mplayer=*)
					MPLAYER_BIN=$(realpathr "$(cut -d'=' -f2<<<"$2")")
					assert '[[ -x $MPLAYER_BIN ]]'
					warn "[U] MPLAYER_BIN=$MPLAYER_BIN"
					;;
				# Ignore one of the players
				disable_ffmpeg)
					FFMPEG_BIN=''
					CAPTURERS_AVAIL=( $(sed 's/ffmpeg//'<<<"${CAPTURERS_AVAIL[*]}") )
					warn "FFmpeg disabled"
					assert '[[ $MPLAYER_BIN ]]'
					set_capturer mplayer
					;;
				disable_mplayer)
					MPLAYER_BIN=''
					CAPTURERS_AVAIL=( $(sed 's/mplayer//'<<<"${CAPTURERS_AVAIL[*]}") )
					warn "Mplayer disabled"
					assert '[[ $FFMPEG_BIN ]]'
					set_capturer ffmpeg
					;;
				debug)
					warn "[U] debug"
					DEBUG=1
					;;
				trace=*) # (Implies 'debug'), traces a particular function name
					INTERNAL_TRACE_FILTER=$(cut -d'=' -f2 <<<"$2")
					DEBUG=1
					warn "[U] debug, tracing '$INTERNAL_TRACE_FILTER'"
					;;
				# Dump user-set variables and exit [since 1.12]
				uservars)
					echo "${OVERRIDE_MAP[*]}" | stonl | egrep -v '(deprecated=|alias)' | cut -d':' -f1-2 |\
					 while read ovname ; do
						f=${ovname/:*}
						t=${ovname#*:}
						if [[ ( $t ) && ( $t != '=' ) ]]; then f="$t" ; fi
						eval v=\$USR_$f
						[[ -z $v ]] || echo "$(tolower $f)=$v"
					done
					exit 0
					;;
				functest) # Test a function: -Z functest <funcname> <arg> [arg] [...]
					shift 3 # We're quitting anyway
					funcname=$1
					shift
					if [[ $(type -t "$funcname") != 'function' ]]; then
						error "functest can only test actual functions"
						exit $EX_USAGE
					fi
					inf "Testing $funcname($*)"
					$funcname "$@"
					exit 0
					;;
				display) UNDFLAG_DISPLAY=1 ;;
				discard) UNDFLAG_DISCARD=1 ;;
				*)
					error "Unknown \`--undocumented $2' option"
				;;
			esac
			shift
			;;
		--generate)
			case "$2" in
				profile|config)
					POST_GETOPT_HOOKS=( "${POST_GETOPT_HOOKS[@]}" \
									10:generate_config:$2 )
					;;
				*)
					error "Option --generate must be followed by profile or config"
					exit $EX_USAGE
					;;
			esac
			shift
			;;
		-D) # Repeat to just test consistency
			if [[ $DEBUGGED -gt 0 ]]; then
				pick_tools # Simulate a normal run
				infplain '[ svn $Rev: 688 $ ]'
				# Even when empty, POSIXLY_CORRECT has an effect, check if it's
				# set ([[BIS]])
				if [[ -n ${POSIXLY_CORRECT+x} ]]; then
					pc="'${POSIXLY_CORRECT}'"
				else
					pc='{not set}'
				fi
				# AWK and sed version can't be checked in all variants
				awkv=$(awk --version 2>/dev/null | head -1) || true
				if [[ -n $awkv ]]; then
					awkv="${NL}AWK:                $awkv"
				fi
				sedv=$(sed --version 2>/dev/null | head -1) || true
				if [[ -n $sedv ]]; then
					sedv="${NL}sed:                $sedv"
				fi
				usrcap=
				if [[ -n $USR_CAPTURER ]]; then
					usrcap=$USR_CAPTURER
				else
					usrcap='{default}'
				fi
				evasion="Enabled (${EVASION_ALTERNATIVES[*]})"
				if [[ $DISABLE_EVASION -eq 1 ]]; then
					evasion='Disabled'
				fi
				if type -paf lsb_release >/dev/null ; then
					lsb_release=$(lsb_release -d | cut -d: -f2- | sed 's/^[[:space:]]*//')
				fi
				imversion=$(convert --version | head -1 | cut -d' ' -f2-)
				if [[ -n "$MPLAYER_BIN" ]]; then
					mpversion=$("$MPLAYER_BIN" --version 2>/dev/null || true)
					# Older mplayer doesn't understand --version...
					if grep "Unknown option" <<<"$mpversion" ; then
						# ...But the last output line contains the version in my sample
						mpversion=$(tail -1 <<<"$mpversion")
					fi
				fi
				if [[ -n "$FFMPEG_BIN" ]]; then
					# Older versions print to stderr, newer to stdout
					ffversion=$("$FFMPEG_BIN" -version 2>&1 | head -1)
					lavcversion=$("$FFMPEG_BIN" -version 2>&1 | grep libavcodec \
								  | sed 's/[[:space:]][[:space:]]*/ /')
					ffversion="$ffversion / $lavcversion"
				fi
				cat >&2 <<-EOD
					=== Setup ===
					GETOPT:             $GETOPT
					MPLAYER:            $MPLAYER_BIN
					FFMPEG:             $FFMPEG_BIN
					AWK:                $(realpathr $(type -pf awk))
					sed:                $(realpathr $(type -pf sed))
					POSIXLY_CORRECT:    $pc
					Capturers (av.):    [ ${CAPTURERS_AVAIL[*]} ]
					Identif. (av.):     [ ${IDENTIFIERS_AVAIL[*]} ]
					Capturer:           $CAPTURER
					Chosen capturer:    $usrcap
					Filterchain:        [ ${FILTERS_IND[*]} ]
					Safe step:          $QUIRKS_LEN_STEP
					Blank evasion:      $evasion
					=== Versions ===
					Bash:               $BASH_VERSION
					Getopt:             $($GETOPT --version)$awkv$sedv
					MPlayer:            $mpversion
					FFMpeg:             $ffversion
					ImageMagick:        $imversion
					LSB Description:    $lsb_release
EOD
				exit
			fi
			DEBUG=1
			VERBOSITY=$V_ALL
			inf "Testing internal consistency..."
			tmp=$INTERNAL_NO_TRACE
			INTERNAL_NO_TRACE=1 # Avoid any tracing during the test
			internal_integrity_test && warn "All tests passed" || error "Some tests failed!"
			INTERNAL_NO_TRACE=$tmp
			unset tmp
			DEBUGGED=1
			warn "Command line: $0 $ARGS"
			TITLE="$(basename "$0") $ARGS"
			;;
		--) shift ; break ;;
		*) error "Internal error! (remaining opts: $*)" ; exit $EX_SOFTWARE ;
	esac
	shift
done

# Avoid coherence_check if there's no arguments and no cmdline post
# processing
[[ -n $1 || -n $POST_GETOPT_HOOKS ]] || {
	[[ $VERBOSITY -eq $V_NONE ]] || show_help
	exit $EX_USAGE
}

# More than one argument...
if [[ -n $2 ]]; then
	multiple_input_files=1
fi
# }}} # Command line parsing

# The coherence check ensures the processed options are
# not incoherent/incompatible with the input files or with
# other given options
coherence_check || {
	exit $?
}
# Run after coherence check to clean recoverable incorrect values
post_getopt_hooks

pick_tools

# Remaining arguments
if [[ -z $1 ]]; then
	[[ $VERBOSITY -eq $V_NONE ]] || show_help
	exit $EX_USAGE
fi

# TODO:
# DVD mode + multiple titles is still tricky:
# --dvd --dvd-title 1 --dvd-title 2 /dev/dvd /dev/dvd

set +e # Don't fail automatically. Blocks marked with {{SET_E}} will break if this changes
for arg do process "$arg" ; done

# Script ends here, everything below are comments
# ===========================================================================
#
# Bash syntax notes # {{{
# These are some notes for my own reference (or for those trying to read the script)
# regarding bash syntax nuissances.
#
# * see http://www.gnu.org/s/bash/manual/html_node/Bash-Variables.html for builtin vars
# * herestring redirection, '<<<$string', (used extensively in vcs) was introduced in bash 2.05b
# * sed s/[ ,]/ * /g <=> ${var//[ ,]/ * }      [Much faster due to not forking]
#   sed s/[ ,]/ * /  <=> ${var/[ ,]/ * }
# * bash2: declaring local empty arrays like 'local a=( )' makes bash think they're strings
#          'local -a' must be used instead
#          bash3 has no problem with this
# * bash2: 'arr+=( elem )' for array push is not supported, use 'arr=( "${arr[@]}" elem )' instead
#          += is a bash3 syntax modification, bash3.1 extended it further, arithmetic += works
#          inside let
# * bash2: [*] expands as a string while [@] expands as an array. Both have trouble with spaces
#          in elements though
# * bash3: [[ STR =~ EREGEX ]] is faster than grep/egrep (no forking)
#          bash 3.2 changed semantics vs bash 3.1
#          quoting the ERE poses a problem (newer bash will interpret as plain string, older
#          as ERE), storing the ERE in a variable or writing it unquoted solves this problem
# * bash4: |& (inherited from csh?) pipes both stdout and stderr
# * [[ A == $B ]] : $B should be quoted usually, otherwise it will be scanned as a regex
# * performance: bash loops are often slower than awk or perl
# * performance: grep + cut proved faster than an equivalent sed -r s// replacement
# }}} # Bash syntax notes
#
# vim:set ts=4 ai foldmethod=marker nu: #
