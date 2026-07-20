#!/usr/bin/env bash
#
# Bootstrap do Akvorado for Lazy em uma VM Rocky Linux 9 nova.
#
# O que este script faz:
#   1. Instala as dependências do sistema (Docker Engine + plugin compose, git)
#   2. Clona (ou atualiza) o repositório em /opt/akvorado
#   3. Pergunta um usuário e uma senha únicos, usados em todos os serviços
#      que exigem autenticação (ClickHouse e Redis)
#   4. Builda as imagens e sobe a stack completa
#
# Uso recomendado (baixar e depois executar, para os prompts funcionarem
# corretamente mesmo se você copiar/colar o comando via curl):
#
#   curl -fsSL https://raw.githubusercontent.com/0LB-i/akvorado-for-lazy/main/bootstrap.sh -o bootstrap.sh
#   sudo bash bootstrap.sh
#
set -euo pipefail

REPO_URL="https://github.com/0LB-i/akvorado-for-lazy.git"
INSTALL_DIR="/opt/akvorado"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Execute este script como root: sudo bash bootstrap.sh"
        exit 1
    fi
}

detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Não foi possível detectar o sistema operacional (/etc/os-release ausente)."
        exit 1
    fi
    . /etc/os-release
    if [ "${ID:-}" != "rocky" ] && [[ "${ID_LIKE:-}" != *rhel* ]]; then
        log_warn "Este script foi feito para Rocky Linux 9. Sistema detectado: ${PRETTY_NAME:-desconhecido}"
        read -r -p "Continuar mesmo assim? (s/N) " CONTINUE < /dev/tty
        [[ "$CONTINUE" =~ ^[Ss]$ ]] || exit 1
    fi
}

install_dependencies() {
    log_info "Instalando dependências do sistema..."
    dnf -y install dnf-plugins-core curl git tar

    if ! command -v docker &> /dev/null; then
        log_info "Instalando Docker Engine..."
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable --now docker
    else
        log_info "Docker já está instalado: $(docker --version)"
        systemctl enable --now docker
    fi

    # Permite usar docker sem sudo para o usuário que chamou o sudo (se houver)
    local target_user="${SUDO_USER:-}"
    if [ -n "$target_user" ] && [ "$target_user" != "root" ]; then
        usermod -aG docker "$target_user" || true
        log_warn "Usuário '$target_user' adicionado ao grupo docker (é preciso logout/login para valer sem sudo)."
    fi
}

clone_repo() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        log_info "Repositório já existe em $INSTALL_DIR, atualizando..."
        git -C "$INSTALL_DIR" pull --ff-only
    else
        log_info "Clonando repositório em $INSTALL_DIR..."
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
}

generate_password() {
    if command -v openssl &> /dev/null; then
        openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
    else
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24
    fi
}

# Aceita apenas caracteres seguros em qualquer contexto onde a senha é
# usada (YAML, sed, shell, .env) - evita ter que escapar nada depois.
is_safe_credential() {
    [[ "$1" =~ ^[A-Za-z0-9._%+=@-]+$ ]]
}

configure_credentials() {
    echo ""
    log_info "========================================"
    log_info "Credenciais do banco de dados"
    log_info "========================================"
    log_info "Usuário e senha únicos, usados em todos os serviços que pedem"
    log_info "autenticação (ClickHouse e Redis)."
    echo ""

    read -r -p "Usuário do banco de dados [akvorado]: " DB_USER < /dev/tty
    DB_USER=${DB_USER:-akvorado}
    if ! is_safe_credential "$DB_USER"; then
        log_error "Usuário inválido. Use apenas letras, números e . _ % + = @ -"
        exit 1
    fi

    read -r -s -p "Senha (deixe em branco para gerar uma automaticamente): " DB_PASSWORD < /dev/tty
    echo "" > /dev/tty
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(generate_password)
        log_info "Senha gerada automaticamente."
    else
        if ! is_safe_credential "$DB_PASSWORD" || [ "${#DB_PASSWORD}" -lt 8 ]; then
            log_error "Senha inválida. Mínimo 8 caracteres, apenas letras, números e . _ % + = @ -"
            exit 1
        fi
        local DB_PASSWORD_CONFIRM
        read -r -s -p "Confirme a senha: " DB_PASSWORD_CONFIRM < /dev/tty
        echo "" > /dev/tty
        if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
            log_error "As senhas não conferem."
            exit 1
        fi
    fi

    cd "$INSTALL_DIR"
    if [ ! -f .env ]; then
        cp .env.example .env
    fi

    # Reescreve só as 3 chaves de credencial, sem depender de sed (evita
    # qualquer problema de escaping de caracteres especiais na senha)
    grep -v -E '^(CLICKHOUSE_USER|CLICKHOUSE_PASSWORD|REDIS_PASSWORD)=' .env > .env.tmp || true
    {
        cat .env.tmp
        echo "CLICKHOUSE_USER=${DB_USER}"
        echo "CLICKHOUSE_PASSWORD=${DB_PASSWORD}"
        echo "REDIS_PASSWORD=${DB_PASSWORD}"
    } > .env
    rm -f .env.tmp

    # Força a regeneração do config/akvorado-orchestrator.yaml a partir do
    # template com as credenciais atuais (scripts/install.sh faz isso
    # automaticamente quando o arquivo não existe)
    rm -f config/akvorado-orchestrator.yaml

    log_info "Credenciais salvas em $INSTALL_DIR/.env"
    echo ""
    log_warn "Guarde essa senha em local seguro, ela não será exibida de novo:"
    echo -e "  Usuário: ${DB_USER}"
    echo -e "  Senha:   ${DB_PASSWORD}"
    echo ""
    read -r -p "Pressione Enter para continuar..." _ < /dev/tty
}

run_install() {
    cd "$INSTALL_DIR"
    chmod +x scripts/*.sh
    log_info "Construindo e iniciando a stack Akvorado (scripts/install.sh)..."
    ./scripts/install.sh
}

main() {
    echo ""
    log_info "========================================"
    log_info "Bootstrap - Akvorado for Lazy"
    log_info "========================================"
    echo ""

    require_root
    detect_os
    install_dependencies
    clone_repo
    configure_credentials
    run_install
}

main
