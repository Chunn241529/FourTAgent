#!/bin/bash
# Script ép Linux sử dụng Local Time cho phần cứng
echo "Đang điều chỉnh hệ thống để đồng bộ giờ với Windows..."
timedatectl set-local-rtc 1 --adjust-system-clock

echo "Trạng thái hiện tại:"
timedatectl
