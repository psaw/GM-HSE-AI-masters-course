#!/bin/bash

yc config profile activate prod

# Константы
VM_ID="fhmcts6gt5k6bmsvfdl9"
SECURITY_GROUP_ID="enpl8ref208ejb00pdh5"
SSH_RULE_ID="enpfo821otvc3lqh9i38"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода справки
show_help() {
    echo -e "${BLUE}Скрипт для управления ВМ в Яндекс Облаке${NC}"
    echo ""
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  -s, --start          Запустить виртуальную машину"
    echo "  -t, --stop           Остановить виртуальную машину"
    echo "  -r, --restart        Перезапустить виртуальную машину"
    echo "  -i, --ip             Получить текущий IP адрес"
    echo "  -u, --update-sg      Обновить группу безопасности с текущим IP"
    echo "  -a, --all            Запустить ВМ и обновить группу безопасности"
    echo "  -h, --help           Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 --start           # Только запустить ВМ"
    echo "  $0 --stop            # Только остановить ВМ"
    echo "  $0 --all             # Запустить ВМ и обновить группу безопасности"
    echo "  $0 --update-sg       # Только обновить группу безопасности"
}

# Функция для логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Функция для вывода ошибок
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Функция для вывода предупреждений
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Функция для получения текущего IP адреса
get_current_ip() {
    local ip=$(curl -s http://2ip.ru 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
    else
        return 1
    fi
}

# Функция для получения и вывода публичного IP виртуальной машины
show_vm_ip() {
    log "Получение публичного IP виртуальной машины..."
    local vm_ip=$(yc compute instance get $VM_ID --format json 2>/dev/null | grep -A 10 "one_to_one_nat" | grep "address" | head -n 1 | awk -F'"' '{print $4}')
    
    if [ -n "$vm_ip" ]; then
        echo -e "${BLUE}┌─────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│${NC} Публичный IP виртуальной машины:        ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC} ${GREEN}${vm_ip}${NC}$(printf '%*s' $((37 - ${#vm_ip})) '')   ${BLUE}│${NC}"
        echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
    else
        warning "Не удалось получить публичный IP виртуальной машины (возможно, ВМ остановлена или нет внешнего IP)"
    fi
}

# Функция для запуска виртуальной машины
start_vm() {
    log "Запуск виртуальной машины $VM_ID..."
    
    # Проверяем статус ВМ
    local status=$(yc compute instance get $VM_ID --jq '.status' 2>/dev/null)
    
    if [ "$status" = "RUNNING" ]; then
        warning "Виртуальная машина уже запущена"
        show_vm_ip
        return 0
    fi
    
    # Запускаем ВМ
    if yc compute instance start $VM_ID --no-user-output; then
        log "Виртуальная машина успешно запущена"
        
        # Ждем пока ВМ полностью запустится
        log "Ожидание полного запуска ВМ..."
        while [ "$(yc compute instance get $VM_ID --jq '.status' 2>/dev/null)" != "RUNNING" ]; do
            sleep 2
        done
        log "ВМ полностью запущена"
        show_vm_ip
    else
        error "Не удалось запустить виртуальную машину"
        return 1
    fi
}

# Функция для остановки виртуальной машины
stop_vm() {
    log "Остановка виртуальной машины $VM_ID..."
    
    # Проверяем статус ВМ
    local status=$(yc compute instance get $VM_ID --jq '.status' 2>/dev/null)
    
    if [ "$status" = "STOPPED" ]; then
        warning "Виртуальная машина уже остановлена"
        return 0
    fi
    
    # Останавливаем ВМ
    if yc compute instance stop $VM_ID --no-user-output; then
        log "Виртуальная машина успешно остановлена"
    else
        error "Не удалось остановить виртуальную машину"
        return 1
    fi
}

# Функция для перезапуска виртуальной машины
restart_vm() {
    log "Перезапуск виртуальной машины $VM_ID..."
    stop_vm && start_vm
}

# Функция для обновления группы безопасности
update_security_group() {
    log "Обновление группы безопасности $SECURITY_GROUP_ID..."
    
    # Получаем текущий IP
    log "Получение текущего IP адреса..."
    local current_ip=$(get_current_ip)
    if [ $? -ne 0 ]; then
        error "Не удалось получить IP адрес"
        return 1
    fi
    
    log "Текущий IP: $current_ip"
    
    # Формируем CIDR
    local cidr="$current_ip/32"
    log "Добавление IP $cidr в группу безопасности..."
    
    # Добавляем новое правило в группу безопасности
    local current_date=$(date -Iseconds)
    if yc vpc security-group update-rules $SECURITY_GROUP_ID --add-rule "description=SSH-$current_date,direction=ingress,protocol=tcp,to-port=22,from-port=22,v4-cidrs=$cidr" --no-user-output; then
        log "Группа безопасности успешно обновлена с IP $cidr"
        show_vm_ip
    else
        error "Не удалось обновить группу безопасности"
        return 1
    fi
}

# Функция для выполнения всех операций (запуск + обновление группы безопасности)
do_all() {
    log "Выполнение всех операций..."
    start_vm && update_security_group
}

# Проверка наличия необходимых утилит
check_dependencies() {
    local missing_deps=()
    
    if ! command -v yc &> /dev/null; then
        missing_deps+=("yc")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Отсутствуют необходимые утилиты: ${missing_deps[*]}"
        error "Установите их перед использованием скрипта"
        return 1
    fi
}

# Основная логика
main() {
    # Проверяем зависимости
    if ! check_dependencies; then
        exit 1
    fi
    
    # Если не передано ни одного аргумента, показываем справку
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    # Обработка аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--start)
                start_vm
                shift
                ;;
            -t|--stop)
                stop_vm
                shift
                ;;
            -r|--restart)
                restart_vm
                shift
                ;;
            -i|--ip)
                get_current_ip
                show_vm_ip
                shift
                ;;
            -u|--update-sg)
                update_security_group
                shift
                ;;
            -a|--all)
                do_all
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Запуск основной функции
main "$@"
