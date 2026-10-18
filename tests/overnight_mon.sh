#!/bin/zsh
# NOTA: valores do ambiente de teste do autor — ajuste IPs/hostname ao seu caso.
# 192.168.1.100 = cliente/coletor; en0 = interface Wi-Fi do Mac.
# overnight_mon.sh - monitora o AX1800 por ~8h com testes leves horarios
B=/private/var/folders/14/38144zv502g1mwl7d4mvf9dh0000gn/T/opencode
LOG="$B/overnight.log"
SUM="$B/overnight_summary.txt"
SSHOPTS=(-4 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o NumberOfPasswordPrompts=0 -o LogLevel=ERROR)

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }
sshq() { perl -e 'alarm shift; exec @ARGV' 20 ssh "${SSHOPTS[@]}" root@192.168.31.1 "$@"; }

log "=== overnight_mon start ==="
PREV_U=0; PREV_K=0; REBOOTS=0; MAXK=0; CYC=0; OKC=0; CF=0; RF=0
TP_C=""; TP_R=""; LC_C=""; LC_R=""
MINF=99999999; MINA=99999999

for i in $(seq 1 48); do
  CYC=$((CYC+1))
  pc=F; pr=F
  ping -c2 -t 3 192.168.31.1 >/dev/null 2>&1 && pc=OK
  ping -b en0 -c2 -t 4 192.168.1.2 >/dev/null 2>&1 && pr=OK
  ST=$(sshq /usr/local/bin/check.sh 2>/dev/null)
  if [ -n "$ST" ]; then
    eval "$ST"
    log "cyc=$CYC cable=$pc relay=$pr U=$U F=$F A=$A K=$K G=$G S=$S R=$R SIG=$SG NET=$NET"
    [ "$F" -lt "$MINF" ] 2>/dev/null && MINF=$F
    [ "$A" -lt "$MINA" ] 2>/dev/null && MINA=$A
    if [ "$K" -gt "$PREV_K" ]; then
      log "!! OOM ALERT: kills $PREV_K -> $K"
      sshq 'dmesg | grep -A25 "invoked oom" | tail -30' >> "$LOG" 2>&1
    fi
    [ "$K" -gt "$MAXK" ] && MAXK=$K
    PREV_K=$K
    if [ "$PREV_U" -gt 0 ] && [ "$U" -lt "$PREV_U" ]; then
      REBOOTS=$((REBOOTS+1))
      log "!! REBOOT detectado (uptime $PREV_U -> $U)"
      sshq 'logread | grep -iE "guard|reboot" | tail -6; echo "--guard-reboots-file--"; cat /etc/guard/reboots' >> "$LOG" 2>&1
      sleep 60
      for k in 1 2 3 4 5 6; do ping -c2 -t 3 192.168.31.1 >/dev/null 2>&1 && break; sleep 20; done
      log "   pos-reboot: ping cable=$?"
    fi
    PREV_U=$U
    [ "$pc" = OK ] && [ "$pr" = OK ] && [ "$S" = 1 ] && [ "$R" = 1 ] && OKC=$((OKC+1))
    if [ "$pc" = F ]; then CF=$((CF+1)); else CF=0; fi
    if [ "$pr" = F ]; then RF=$((RF+1)); else RF=0; fi
    [ "$CF" -ge 3 ] && log "!! cable inacessivel ha $CF ciclos (box travado? guard deve reiniciar)"
    [ "$RF" -ge 3 ] && log "!! relay wifi inacessivel ha $RF ciclos (cabo=$pc) - guard deve reiniciar se STA morta"
  else
    log "cyc=$CYC cable=$pc relay=$pr SSH_FAIL"
    RCHK=$(perl -e 'alarm shift; exec @ARGV' 12 ssh "${SSHOPTS[@]}" -b 192.168.1.100 root@192.168.1.2 'echo ROK' 2>/dev/null)
    log "   ssh relay=${RCHK:-FAIL}"
    if [ "$pc" = F ]; then CF=$((CF+1)); else CF=0; fi
    [ "$CF" -ge 3 ] && log "!! box travado ha $CF ciclos — guard reinicia em ~6min"
  fi
  if [ $((CYC % 6)) -eq 0 ] && [ -n "$ST" ]; then
    TP=$(sshq 'sh -s' <<'EOS' 2>/dev/null
r0=$(cat /sys/class/net/br-lan/statistics/rx_bytes); t0=$(cut -d' ' -f1 /proc/uptime)
wget -T 20 -q -O /dev/null http://192.168.31.100:8123/small4m.bin
t1=$(cut -d' ' -f1 /proc/uptime); r1=$(cat /sys/class/net/br-lan/statistics/rx_bytes)
awk -v a=$t0 -v b=$t1 -v x=$r0 -v y=$r1 'BEGIN{d=b-a;by=y-x;printf "TPCABO=%.1f\n", by*8/d/1e6}'
r0=$(cat /sys/class/net/phy0-sta0/statistics/rx_bytes); t0=$(cut -d' ' -f1 /proc/uptime)
wget -T 20 -q -O /dev/null http://192.168.1.100:8123/small4m.bin
t1=$(cut -d' ' -f1 /proc/uptime); r1=$(cat /sys/class/net/phy0-sta0/statistics/rx_bytes)
awk -v a=$t0 -v b=$t1 -v x=$r0 -v y=$r1 'BEGIN{d=b-a;by=y-x;printf "TPREL=%.1f\n", by*8/d/1e6}'
EOS
)
    CTP=$(echo "$TP" | grep TPCABO | cut -d= -f2)
    RTP=$(echo "$TP" | grep TPREL | cut -d= -f2)
    LCC=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://192.168.31.1/ 2>/dev/null)
    LCR=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --interface en0 http://192.168.1.2/ 2>/dev/null)
    log "   leve: cabo=${CTP}Mbps relay=${RTP}Mbps luci_cabo=$LCC luci_relay=$LCR"
    TP_C="$TP_C $CTP"; TP_R="$TP_R $RTP"; LC_C="$LC_C $LCC"; LC_R="$LC_R $LCR"
  fi
  sleep 540
done

{
  echo "=== RESUMO OVERNIGHT AX1800 $(date '+%F %T') ==="
  echo "ciclos: $CYC | ciclos 100% ok (cabo+relay+sta+relayd): $OKC"
  echo "reboots detectados: $REBOOTS"
  echo "max OOM kills (acumulado dmesg): $MAXK"
  echo "free minimo: ${MINF}kB | avail minimo: ${MINA}kB"
  echo "throughput cabo (Mbps, 4MB):$TP_C"
  echo "throughput relay (Mbps, 4MB):$TP_R"
  echo "luci cabo (http):$LC_C"
  echo "luci relay (http):$LC_R"
  echo "--- ultimas linhas do log ---"
  tail -25 "$LOG"
} > "$SUM"
log "=== overnight_mon fim ==="
echo "SUMMARIO:"
cat "$SUM"
