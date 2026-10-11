# =====================================================================
#  chr-container.rsc  -  Phase 2: 3x-ui container (after device-mode reboot)
#  /import chr-container.rsc
# =====================================================================

# ------------------------- PARAMETERS (edit) -------------------------
:local DISK      "disk1"
# pin a tag instead of :latest for reproducible installs
:local IMAGE     "bigbugcc/3x-ui:latest"
# Docker Hub blocks Iranian IPs. If pull fails, put a reachable mirror here
# (e.g. a domestic Docker mirror) or upload an image .tar and use FILE.
:local REGISTRY  "https://registry-1.docker.io"
:local FILE      ""
# ---------------------------------------------------------------------

:if ([/system device-mode get container] != true) do={ :error "device-mode container is not enabled yet (cold reboot needed)" }

/container config set registry-url=$REGISTRY tmpdir=($DISK . "/pull")

# persistent DB: image declares VOLUME /etc/x-ui (x-ui.db lives there)
/container mounts add list=MOUNT_XUI src=("/" . $DISK . "/xui") dst=/etc/x-ui
/container envs add list=ENV_XUI key=TZ value=Asia/Tehran

:if ($FILE = "") do={
  /container add remote-image=$IMAGE interface=veth1 root-dir=($DISK . "/containers/3x-ui") \
      dns=8.8.8.8,1.1.1.1 workdir=/app start-on-boot=yes logging=yes name=xui \
      mountlists=MOUNT_XUI envlists=ENV_XUI ignore-remote-image-change=yes
} else={
  /container add file=$FILE interface=veth1 root-dir=($DISK . "/containers/3x-ui") \
      dns=8.8.8.8,1.1.1.1 workdir=/app start-on-boot=yes logging=yes name=xui \
      mountlists=MOUNT_XUI envlists=ENV_XUI
}

:put "waiting for image pull/extract (up to 10 min)..."
:local ok false
:local n 0
:while ($ok = false && $n < 120) do={
  :delay 5s
  :set n ($n + 1)
  :do { /container start [find name=xui]; :set ok true } on-error={}
}
:if ($ok) do={
  :put "chr-container: started. Panel: http://<WAN-IP>:<PANELPORT>"
} else={
  :put "chr-container: could not start yet - check: /container print / /log print where topics~\"container\""
}
