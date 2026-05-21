import time
import psutil
import requests
from datetime import datetime, timezone

# Gnocchi 설정
GNOCCHI_URL = "http://192.168.0.121:8041"
METRIC_ID = "3c9b32b8-bab1-4c11-934d-d3de39e9a72f"  # 예: CPU 사용률 메트릭 ID
AUTH = ('admin', '') # 단일 Gnocchi 배포 시 설정한 auth_mode = basic [cite: 385, 487]

def get_real_cpu_usage():
    # psutil을 사용하여 1초 동안의 평균 CPU 사용률을 측정 [cite: 199]
    return psutil.cpu_percent(interval=1)

def send_measure_to_gnocchi(metric_id, value):
    url = f"{GNOCCHI_URL}/v1/metric/{metric_id}/measures"
    
    # Gnocchi가 요구하는 ISO 8601 포맷으로 현재 시간 생성
    current_time = datetime.now(timezone.utc).astimezone().isoformat()
    
    payload = [
        {
            "timestamp": current_time,
            "value": value
        }
    ]
    
    try:
        response = requests.post(url, json=payload, auth=AUTH)
        response.raise_for_status()
        print(f"[{current_time}] 데이터 전송 성공: CPU {value}%")
    except requests.exceptions.RequestException as e:
        print(f"[{current_time}] 데이터 전송 실패: {e}")

if __name__ == "__main__":
    print("CRMS 임시 자동화 에이전트를 시작합니다... (종료: Ctrl+C)")
    
    # 1분 단위 수집 (설계 문서의 guest_detailed 정책 5분 단위의 기반이 될 수 있음) [cite: 73, 164]
    INTERVAL_SECONDS = 60 

    while True:
        try:
            # 1. 실제 데이터 수집
            cpu_usage = get_real_cpu_usage()
            
            # 2. Gnocchi로 전송
            send_measure_to_gnocchi(METRIC_ID, cpu_usage)
            
            # 3. 대기
            time.sleep(INTERVAL_SECONDS - 1) # cpu_percent(interval=1)에서 1초를 소모하므로 59초 대기
            
        except KeyboardInterrupt:
            print("\n수집을 종료합니다.")
            break
        except Exception as e:
            print(f"예기치 않은 에러 발생: {e}")
            time.sleep(5) # 에러 시 잠시 대기 후 재시도