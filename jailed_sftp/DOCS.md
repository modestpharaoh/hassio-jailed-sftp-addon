# Jailed SFTP Add-on Documentation

## About

This add-on provides a secure, jailed SFTP server for Home Assistant. Each user is restricted to their own directory and cannot access files outside of it.

## Configuration

The add-on is configured through the Home Assistant UI. Here are the available options:

### Main Options

| Parameter | Required | Description |
|-----------|----------|-------------|
| `log_level` | No | Log level (trace, debug, info, notice, warning, error, fatal). Default: `info` |

### Users

Define one or more SFTP users with the following parameters:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `username` | Yes | The username for SFTP login |
| `password` | No* | Password for authentication |
| `ssh_key` | No* | List of SSH public keys for key-based authentication |
| `parent_directory` | Yes | Parent directory for the user: `share` or `media` |
| `sub_directory` | No | Optional writable subdirectory to create inside the user's home |

*At least one of `password` or `ssh_key` must be provided.

### Example Configuration

```yaml
log_level: info
users:
  - username: "alice"
    password: "secretpassword"
    parent_directory: "media"
    sub_directory: "files"
  - username: "bob"
    ssh_key:
      - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... bob@example.com"
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... bob@laptop"
    parent_directory: "share"
```

## How It Works

### Directory Structure

When a user is configured with a `parent_directory` (e.g., `media`), the add-on:

1. Creates a directory `/<parent_directory>/<username>` (e.g., `/media/alice`)
2. Sets ownership to `root:root` with permissions `755` (required for chroot security)

If `sub_directory` is specified (e.g., `files`):
3. Creates `/<parent_directory>/<username>/files`
4. Sets ownership to `<username>:sftp-users` with permissions `750`

When the user connects via SFTP:
- They see `/` as their root directory (which is actually `/media/alice` on the system)
- They **cannot** escape to parent directories
- The root `/` is **Read-Only** (owned by root).
- If `sub_directory` was configured, they can write to that folder (e.g., `/files`).

### Authentication

The add-on supports two authentication methods:

1. **Password Authentication**: Simple username/password login
2. **SSH Key Authentication**: More secure, key-based authentication

You can use both methods simultaneously for the same user.

### Security Features

- **Chroot Jail**: Users cannot access files outside their designated directory
- **No Shell Access**: Users can only use SFTP, not SSH shell access
- **Disabled Forwarding**: X11, TCP, and agent forwarding are all disabled
- **No Tunneling**: Port tunneling is disabled
- **PAM Disabled**: Simplified authentication without PAM

## Usage

### Connecting via Command Line

```bash
# Using password authentication
sftp -P 222 alice@homeassistant.local

# Using SSH key authentication
sftp -P 222 -i ~/.ssh/id_rsa bob@homeassistant.local
```

### Connection Issues

**Cannot write files:**
The root of a chroot jail is owned by root and is read-only.
- If you didn't specify `sub_directory`, you cannot write to the root.
- If you specified `sub_directory: "upload"`, you must upload files into the `upload` folder.

**Permission denied:**
Check your keys or password.
Check the add-on logs for details. Set `log_level: debug` for more information.
