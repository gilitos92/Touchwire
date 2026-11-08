# Code-signing identity helpers, sourced by Scripts/build.sh and Scripts/publish-release.sh (zsh).
#
# Touchwire is signed with the Developer ID Application certificate of team GC28C3K5G9, and releases are notarized.
# Releases up to 1.2.1 were signed with the self-signed "GGV" certificate.

TEAM_ID=GC28C3K5G9

# Prints the SHA-1 of the first valid "Developer ID Application" identity of the team, or nothing. Choosing it by hash
# keeps codesign unambiguous while an old and a renewed certificate overlap.
find_developer_id_identity() {
    security find-identity -v -p codesigning 2> /dev/null \
        | awk -v team="(${TEAM_ID})\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }'
}

# Succeeds when the identity (a SHA-1 or a certificate name) is a valid Developer ID Application identity of the team.
is_developer_id_identity() {
    [[ -n "$1" && "$1" != "-" ]] || return 1
    security find-identity -v -p codesigning 2> /dev/null \
        | grep -F -- "$1" \
        | grep -F "(${TEAM_ID})\"" \
        | grep -q '"Developer ID Application: '
}
