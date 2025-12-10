#!/usr/bin/with-contenv bashio
set -e

# Logs should include the date/time.
export __BASHIO_LOG_TIMESTAMP="%y-%m-%d %T"

# Set default log level to info
bashio::log.level "info"
if bashio::var.has_value "log_level"; then
  bashio::log.level "$(bashio::config 'log_level')"
fi

# Generate host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

bashio::log.info "Starting Add-on..."

# Parse log level
LOG_LEVEL=$(bashio::config 'log_level')
SSHD_LOG_LEVEL="INFO"

case "$LOG_LEVEL" in
    trace) SSHD_LOG_LEVEL="DEBUG3" ;;
    debug) SSHD_LOG_LEVEL="DEBUG" ;;
    info) SSHD_LOG_LEVEL="INFO" ;;
    notice) SSHD_LOG_LEVEL="VERBOSE" ;;
    warning) SSHD_LOG_LEVEL="ERROR" ;;
    error) SSHD_LOG_LEVEL="ERROR" ;;
    fatal) SSHD_LOG_LEVEL="FATAL" ;;
esac

bashio::log.info "Log Level: $LOG_LEVEL -> SSHD: $SSHD_LOG_LEVEL"

# Prepare sshd_config
cat > /etc/ssh/sshd_config <<EOF
Port 22
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

PermitRootLogin no
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PermitTunnel no
AllowAgentForwarding no
AllowTcpForwarding no
Subsystem sftp internal-sftp
ChrootDirectory %h
ForceCommand internal-sftp
LogLevel $SSHD_LOG_LEVEL

AuthorizedKeysFile /etc/ssh/authorized_keys/%u

EOF

# Create sftp-users group
addgroup -S sftp-users

# Re-implementing the loop using jq for robust object handling, but with bashio logging.
# We access /data/options.json via bashio functions usually, 
# but simply reading it with jq is standard in many add-ons. 
# Let's keep the jq loop structure but replace echo with bashio::log.info

CONFIG_PATH=/data/options.json

if bashio::config.has_value 'users'; then
    for user_b64 in $(jq -r '.users[] | @base64' "$CONFIG_PATH"); do
        
        _jq() {
            echo "${user_b64}" | base64 -d | jq -r "${1}"
        }

        USERNAME=$(_jq '.username')
        PASSWORD=$(_jq '.password // empty')
        PARENT_DIR=$(_jq '.parent_directory')
        SUB_DIR=$(_jq '.sub_directory') # Optional, might be "null" if not present in schema defaults
        
        # Check for null/empty sub_dir
        if [ "$SUB_DIR" = "null" ]; then SUB_DIR=""; fi

        HOME_DIR="/$PARENT_DIR/$USERNAME"
        
        bashio::log.info "Configuring user: $USERNAME"
        bashio::log.info "  - Home: $HOME_DIR"
        bashio::log.info "  - Parent: $PARENT_DIR"
        if bashio::var.has_value "$SUB_DIR"; then
            bashio::log.info "  - Subdir: $SUB_DIR"
        fi

        # Create user if not exists
        if ! id "$USERNAME" >/dev/null 2>&1; then
            adduser -D -s /sbin/nologin -G sftp-users -h "$HOME_DIR" "$USERNAME"
        fi

        # Set password if provided
        if [ "$PASSWORD" != "empty" ] && [ -n "$PASSWORD" ]; then
            echo "$USERNAME:$PASSWORD" | chpasswd
        else
            passwd -u "$USERNAME" 2>/dev/null || true
        fi
        
        # Ensure the ChrootDirectory exists and is owned by root:root
        if [ ! -d "$HOME_DIR" ]; then
            mkdir -p "$HOME_DIR"
        fi
        
        chown root:root "$HOME_DIR"
        chmod 755 "$HOME_DIR"

        # Create user-writable directory inside chroot if configured
        if bashio::var.has_value "$SUB_DIR"; then
            mkdir -p "$HOME_DIR/$SUB_DIR"
            chown "$USERNAME:sftp-users" "$HOME_DIR/$SUB_DIR"
            chmod 750 "$HOME_DIR/$SUB_DIR"
            bashio::log.info "Created user-writable directory: $HOME_DIR/$SUB_DIR"
        fi
        
        # Setup SSH Keys
        KEYS=$(echo "${user_b64}" | base64 -d | jq -r '.ssh_key[]? // empty')
        
        if [ -n "$KEYS" ]; then
            mkdir -p /etc/ssh/authorized_keys
            echo "$KEYS" > "/etc/ssh/authorized_keys/$USERNAME"
            chown root:root "/etc/ssh/authorized_keys/$USERNAME"
            chmod 644 "/etc/ssh/authorized_keys/$USERNAME"
        fi

    done
fi

bashio::log.info "Starting SSHD..."
/usr/sbin/sshd -D -e
