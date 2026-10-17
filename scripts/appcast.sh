#!/usr/bin/env bash
#
# Build Burnbar's Sparkle appcast for one published release.
#
# What this script is allowed to do: fetch the live feed, fetch and verify the
# pinned signing tool, sign one zip, merge one item, and write the result to an
# output directory. What it deliberately cannot do: publish, tag, retract, or
# select a repository. There is no `git` and no `gh` in it, and
# `AppcastScriptContractTests` asserts both — the release workflow's guarantee
# that it can only ever *create* a release is only worth something if the
# scripts it calls cannot quietly widen it.
#
# It never traces itself. Command tracing would echo the signing pipeline into
# the job log, and the signing pipeline is where the private key is.
#
# Two modes, chosen by the first argument:
#   scripts/appcast.sh fetch   fetch and validate the live feed into
#                              CURRENT_FEED_FILE, then stop. The release workflow
#                              runs this *before* `gh release create`, so a feed
#                              that cannot be read stops the run while nothing is
#                              public yet.
#   scripts/appcast.sh         build: sign, merge and emit. It reads
#                              CURRENT_FEED_FILE when that is set (CI, after the
#                              release exists, never touching the network for the
#                              feed again); when it is unset it fetches the feed
#                              itself with the same rules (a local run).
#
# Environment contract:
#   VERSION              marketing version, without the leading v (1.2.3)
#   BUILD_NUMBER         the build number the release was archived with
#   GITHUB_REF_NAME      the tag; a hyphen in it means prerelease, and no item
#   ASSET_URL            the published zip's download URL
#   ZIP_PATH             the local zip that was published, to be signed
#   FEED_URL             the live feed, fetched so history is preserved;
#                        required whenever this run fetches it
#   CURRENT_FEED_FILE    the pre-fetched feed: written by `fetch`, read by the
#                        build; optional for the build
#   FEED_FETCH_RETRY_DELAY  seconds before the first retry (default 5); the
#                        delay doubles on each later one
#   OUTPUT_DIR           where appcast.xml is written; never the repository tree
#   SPARKLE_PRIVATE_KEY  the EdDSA private key, read on **stdin only**
#
# Run it by hand exactly as CI runs it: every input is an environment variable
# and nothing is discovered from the checkout.

set -euo pipefail

MODE="${1:-build}"
case "$MODE" in
	fetch | build) ;;
	*)
		echo "usage: scripts/appcast.sh [fetch]" >&2
		exit 2
		;;
esac

# --- guard -------------------------------------------------------------------
# The same literal the workflow uses for `--prerelease`, restated here so a hand
# run behaves identically. A prerelease that reached the feed would be offered
# to every stable user; the version comparison alone would not stop that,
# because the feed is the thing being trusted.
case "$GITHUB_REF_NAME" in
	*-*)
		echo "prerelease $GITHUB_REF_NAME: no appcast item, no feed fetch"
		exit 0
		;;
esac

# The pinned signing tool. The version alone would not stop a tampered binary
# from signing the release with an attacker's key, and every installed copy
# would accept the result — the client only checks the signature against the key
# in its own bundle. The digest is what makes that unreachable, and the check
# runs before anything is signed.
SPARKLE_VERSION="2.9.6"
SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
SPARKLE_TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

# The app's own deployment target. It must equal
# `AppcastDocument.expectedMinimumSystemVersion`, and
# `AppcastScriptContractTests` reads both and fails when they disagree: a feed
# emitted with a floor the offline validator rejects is a feed every installed
# copy refuses, discovered only after publication.
MINIMUM_SYSTEM_VERSION="26.5"

# --- fetch -------------------------------------------------------------------
# The merged feed replaces the live one wholesale, so what counts as "no feed
# yet" decides whether history survives. Exactly one answer means that: an HTTP
# 404, the designed state of the very first release, where an empty channel is
# the correct starting point. Every later run merges into whatever is actually
# being served, which is what keeps items for versions a user skipped from
# disappearing.
#
# Everything else stops the run before anything is signed or written: curl
# itself failing (DNS, timeout, TLS), any status other than 200 or 404, and a
# 200 whose body is empty or is not a feed. Treating a transient failure as
# "first release" would replace the live feed with a one-item feed. `curl -f`
# is deliberately not used here: it folds a 404 and a 503 into one exit status.
#
# Every attempt is bounded (`--connect-timeout`, `--max-time`), so a stalled
# endpoint cannot hold the signing job. Transient failures are retried by the
# loop below rather than by curl's own `--retry`: that flag retries timeouts and
# 408/429/5xx, but not a DNS failure or a dropped connection, and its
# `--retry-all-errors` widening would retry a 404 too. Here a retry happens only
# for curl exits 6 (DNS), 7 (connect), 28 (timeout), 35 (TLS handshake), 52
# (empty reply), 55/56 (send/receive) and for HTTP 408, 429 and 5xx. A 200 and a
# 404 are answers, never retried; any other 4xx is refused at once. Four
# attempts, 5 s, 10 s and 20 s apart: worst case about four minutes.
FEED_FETCH_ATTEMPTS=4
FEED_FETCH_RETRY_DELAY="${FEED_FETCH_RETRY_DELAY:-5}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A usable feed: non-empty, with a closing channel tag to insert before.
require_feed() {
	local file="$1" source="$2"
	if [ ! -s "$file" ]; then
		echo "$source is missing or empty; refusing to replace the live feed" >&2
		exit 1
	fi
	case "$(< "$file")" in
		*'</channel>'*) ;;
		*)
			echo "$source has no </channel>; refusing to replace the live feed" >&2
			exit 1
			;;
	esac
}

is_transient() {
	local curl_exit="$1" status="$2"
	case "$curl_exit" in
		6 | 7 | 28 | 35 | 52 | 55 | 56) return 0 ;;
		0) ;;
		*) return 1 ;;
	esac
	case "$status" in
		408 | 429 | 5??) return 0 ;;
		*) return 1 ;;
	esac
}

# Fetch the live feed into $1, or exit 1 having written nothing there.
fetch_feed() {
	local dest="$1" body="$WORK/fetched.xml" attempt=1 delay="$FEED_FETCH_RETRY_DELAY" status curl_exit
	echo "==> fetch $FEED_URL"
	while :; do
		rm -f "$body"
		curl_exit=0
		status="$(curl -sSL --connect-timeout 10 --max-time 60 -w '%{http_code}' -o "$body" "$FEED_URL")" || curl_exit=$?
		if [ "$attempt" -ge "$FEED_FETCH_ATTEMPTS" ] || ! is_transient "$curl_exit" "$status"; then
			break
		fi
		echo "    attempt $attempt: curl exit $curl_exit, HTTP $status; retrying in ${delay}s"
		sleep "$delay"
		attempt=$((attempt + 1))
		delay=$((delay * 2))
	done

	if [ "$curl_exit" -ne 0 ]; then
		echo "could not fetch $FEED_URL (curl exit $curl_exit, $attempt attempt(s)); refusing to replace the live feed" >&2
		exit 1
	fi
	case "$status" in
		200)
			require_feed "$body" "$FEED_URL (HTTP 200)"
			;;
		404)
			echo "    no live feed yet (HTTP 404); starting an empty channel"
			# `<<-` strips leading **tabs** only, so every line of this heredoc,
			# the closing XML included, must be indented with tabs. A space-indented
			# line keeps its spaces, and a closing XML that is not tab-indented
			# never ends the heredoc at all.
			cat > "$body" <<-XML
				<?xml version="1.0" encoding="UTF-8"?>
				<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
					<channel>
						<title>Burnbar</title>
						<description>Updates for Burnbar</description>
						<language>en</language>
					</channel>
				</rss>
			XML
			;;
		*)
			echo "$FEED_URL answered HTTP $status ($attempt attempt(s)); refusing to replace the live feed" >&2
			exit 1
			;;
	esac
	mkdir -p "$(dirname "$dest")"
	mv "$body" "$dest"
}

if [ "$MODE" = fetch ]; then
	FEED_URL="${FEED_URL:?FEED_URL is required}"
	CURRENT_FEED_FILE="${CURRENT_FEED_FILE:?CURRENT_FEED_FILE is required}"
	fetch_feed "$CURRENT_FEED_FILE"
	echo "==> fetched $CURRENT_FEED_FILE"
	exit 0
fi

VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
ASSET_URL="${ASSET_URL:?ASSET_URL is required}"
ZIP_PATH="${ZIP_PATH:?ZIP_PATH is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"

# A pre-fetched feed is read, never re-fetched: in CI the release already exists
# by now, and a missing file means the fetch step did not do its job, not that
# the network should be tried again.
if [ -n "${CURRENT_FEED_FILE:-}" ]; then
	echo "==> read $CURRENT_FEED_FILE"
	require_feed "$CURRENT_FEED_FILE" "the pre-fetched feed $CURRENT_FEED_FILE"
	cp "$CURRENT_FEED_FILE" "$WORK/current.xml"
else
	FEED_URL="${FEED_URL:?FEED_URL is required}"
	fetch_feed "$WORK/current.xml"
fi

# --- tool --------------------------------------------------------------------
echo "==> tool Sparkle $SPARKLE_VERSION"
curl -fsSL -o "$WORK/sparkle.tar.xz" "$SPARKLE_TARBALL_URL"
printf '%s  %s\n' "$SPARKLE_TARBALL_SHA256" "$WORK/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf "$WORK/sparkle.tar.xz" -C "$WORK"

# --- sign --------------------------------------------------------------------
# The key arrives on standard input and is never a file, never an argument, and
# never a redirection target. `--ed-key-file -` exists for exactly this: reading
# the key from a secret environment binding without writing it down anywhere.
# Under `set -u` an unset key aborts here rather than signing with nothing.
echo "==> sign $ZIP_PATH"
FRAGMENT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$WORK/bin/sign_update" --ed-key-file - "$ZIP_PATH")"

# The signing tool's output shape is an input to this script, so it is checked
# rather than assumed. Both attributes are required by Burnbar's offline
# appcast validator; a tool whose output shape changed would otherwise emit an
# item that every installed copy rejects, discovered only after the feed was
# published.
case "$FRAGMENT" in
	*'sparkle:edSignature="'*) ;;
	*) echo "the signing tool emitted no sparkle:edSignature" >&2; exit 1 ;;
esac
case "$FRAGMENT" in
	*'length="'*) ;;
	*) echo "the signing tool emitted no length=" >&2; exit 1 ;;
esac

# --- merge -------------------------------------------------------------------
# One item, prepended, with every prior item preserved in its existing order. A
# bad release is corrected by publishing a higher version, never by deleting a
# feed item: deleting one strands every copy that already saw it.
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# Written to a file rather than passed with `awk -v`: BSD awk rejects a newline
# inside a `-v` value outright, and the runner is macOS.
cat > "$WORK/item.xml" <<-XML
	        <item>
	            <title>Version ${VERSION}</title>
	            <pubDate>${PUB_DATE}</pubDate>
	            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
	            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
	            <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
	            <enclosure url="${ASSET_URL}" ${FRAGMENT} type="application/octet-stream"/>
	        </item>
XML

mkdir -p "$OUTPUT_DIR"
# Inserted before the first existing item, or before the closing channel tag
# when there is none. Newest first, which is the order the offline validator
# requires and the order a merge must not disturb.
awk -v itemfile="$WORK/item.xml" '
	!inserted && ($0 ~ /<item>/ || $0 ~ /<\/channel>/) {
		while ((getline line < itemfile) > 0) { print line }
		close(itemfile)
		inserted = 1
	}
	{ print }
' "$WORK/current.xml" > "$OUTPUT_DIR/appcast.xml"

# --- emit --------------------------------------------------------------------
# Nothing is written into the repository tree, so there is no new stowaway
# surface, no `.gitignore` change, and nothing for a later step to commit.
echo "==> emit $OUTPUT_DIR/appcast.xml"
