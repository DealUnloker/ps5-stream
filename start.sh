#!/bin/bash
# Receives the PS5's Twitch broadcast on this Mac: dnsmasq answers the console's lookups of
# Twitch ingest servers with this Mac's address, MediaMTX accepts the stream and opens it
# in mpv (mediamtx.yml). Ctrl+C stops everything.
set -euo pipefail
cd "$(dirname "$0")"

# dnsmasq returns this Mac's address for these domains and all of their subdomains.
INGEST_DOMAINS=(contribute.live-video.net global-contribute.live-video.net live.twitch.tv)

# Homebrew puts dnsmasq in sbin, which may be missing from PATH.
PATH="$(brew --prefix)/sbin:$PATH"
for dep in dnsmasq mediamtx mpv; do
	command -v "$dep" >/dev/null || { echo "$dep not found: run 'brew bundle'" >&2; exit 1; }
done

lan_ip() {
	local iface
	for iface in $(ifconfig -l); do
		[[ $iface == en* ]] || continue
		ipconfig getifaddr "$iface" 2>/dev/null && return
	done
	return 1
}

ip="${PS5_STREAM_IP:-$(lan_ip)}" || { echo "Could not detect this Mac's LAN address: set PS5_STREAM_IP" >&2; exit 1; }

dns_args=()
for domain in "${INGEST_DOMAINS[@]}"; do
	# --local keeps the query from going upstream: otherwise AAAA returns Twitch's real IPv6.
	dns_args+=("--address=/$domain/$ip" "--local=/$domain/")
done
if [ -n "${PS5_STREAM_DEBUG:-}" ]; then
	dns_args+=(--log-queries)
	export MTX_LOGLEVEL=info
fi

trap 'kill $(jobs -p) 2>/dev/null; wait' EXIT
trap 'exit 130' INT TERM

# Bound to 0.0.0.0: macOS lets a non-root process take port 53 on all addresses, not on a specific one.
# Cache is off: a real address cached from another name's CNAME chain is served in spite of the override.
dnsmasq --keep-in-foreground --conf-file=/dev/null --no-resolv --no-hosts --listen-address=0.0.0.0 \
	--cache-size=0 --server=1.1.1.1 --server=8.8.8.8 --log-facility=- "${dns_args[@]}" &
dns_pid=$!
mediamtx mediamtx.yml &
mtx_pid=$!

alive() { kill -0 "$dns_pid" 2>/dev/null && kill -0 "$mtx_pid" 2>/dev/null; }

sleep 1
alive && cat <<EOF

Ready. This Mac's address: $ip
  PS5 primary DNS: $ip
  Start a Twitch broadcast on the PS5: a window titled "PS5" opens by itself.
  Ctrl+C stops receiving.

EOF

while alive; do sleep 1; done
echo "dnsmasq or MediaMTX exited, stopping" >&2
exit 1
