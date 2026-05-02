#!/command/with-contenv bash
# s6-overlay cont-init 표준 훅 템플릿.
# 설치: /etc/cont-init.d/03-<SERVICE>  (실행 권한 필수, install -m 0755)
#
# 변수 치환:
#   <SERVICE>        서비스 이름 (예: my-app)
#   <PROJECT_ROOT>   PVC 상의 프로젝트 루트 (예: /home/jovyan/my-app)
#   <SUPERVISOR>     start 명령 (예: $PROJECT_ROOT/scripts/supervisor.sh)
#   <BOOT_DELAY>     GPU/네트워크 대기 (초), 일반 앱이면 0~5

set +e
PROJECT_ROOT="<PROJECT_ROOT>"
SUPERVISOR="<SUPERVISOR>"
BOOT_DELAY="<BOOT_DELAY>"
LOG_DIR="$PROJECT_ROOT/_logs"
mkdir -p "$LOG_DIR"

LOG="$LOG_DIR/autostart.log"
{
  echo "=== $(date -Is) <SERVICE> cont-init hook ==="
  # PVC 마운트 대기 (60초까지)
  for i in $(seq 1 30); do
    [ -x "$SUPERVISOR" ] && break
    echo "  PVC 대기... ($i/30)"
    sleep 2
  done

  if [ ! -x "$SUPERVISOR" ]; then
    echo "  ERROR: $SUPERVISOR not found, abort (but exit 0 to not block boot)"
    exit 0
  fi

  # 외부 의존성 안정화 후 백그라운드 분리 시작
  ( sleep "$BOOT_DELAY" && setsid nohup bash "$SUPERVISOR" start \
      >> "$LOG_DIR/autostart-supervisor.log" 2>&1 < /dev/null ) &
  echo "  $SUPERVISOR start 예약 (${BOOT_DELAY}초 후)"
} >> "$LOG" 2>&1

# cont-init은 반드시 0으로 종료. 그렇지 않으면 컨테이너 부팅이 막힌다.
exit 0
