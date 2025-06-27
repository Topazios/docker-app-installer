# Docker Application One-Click Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![GitHub stars](https://img.shields.io/github/stars/Topazios/docker-app-installer.svg)](https://github.com/Topazios/docker-app-installer/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Topazios/docker-app-installer.svg)](https://github.com/Topazios/docker-app-installer/network)

> English | [中文](README.md)

A powerful Docker application one-click installer script that supports rapid deployment, management, and uninstallation of multiple popular applications.

## 🌟 Features

- **🐳 Smart Docker Management**: Automatically detect and install Docker + Docker Compose
- **📦 Multi-App Support**: One-click installation of 5 popular applications
- **🔧 Smart Detection**: Avoid duplicate installations, intelligently handle existing apps
- **🎛️ Interactive Interface**: User-friendly menu interface with command-line parameter support
- **🗑️ Complete Uninstall**: Support app uninstallation with optional data retention
- **🔒 Security Mechanisms**: Permission checks, confirmation mechanisms, error handling
- **📊 Status Monitoring**: Real-time display of application running status

## 📋 Supported Applications

| Application | Description | Default Port | Features |
|-------------|-------------|--------------|----------|
| **Portainer** | Docker Management Interface | 9000 | Visual Docker Management |
| **qBittorrent** | BT Download Tool | 8080 | Torrent Download Management |
| **Vertex** | File Management Download Tool | 3000 | Multi-protocol Download Management |
| **Nginx Proxy Manager** | Reverse Proxy Management | 81 | Domain Reverse Proxy |
| **Transmission** | BT Download Tool | 9091 | Lightweight Torrent Download |

## 🖥️ System Requirements

### Supported Operating Systems
- **Debian**: 10, 11, 12
- **Ubuntu**: 18.04, 20.04, 22.04

### System Requirements
- **Permissions**: Root privileges (sudo)
- **Network**: Stable internet connection
- **Storage**: At least 2GB available space
- **Memory**: Recommended 1GB or more

## 🚀 Quick Start

### 1. Download Script

```bash
# Download using wget
wget https://raw.githubusercontent.com/Topazios/docker-app-installer/main/docker-app-installer.sh

# Or download using curl
curl -O https://raw.githubusercontent.com/Topazios/docker-app-installer/main/docker-app-installer.sh

# Add execute permissions
chmod +x docker-app-installer.sh
```

### 2. Run Script

```bash
# Interactive installation
sudo ./docker-app-installer.sh

# View help
./docker-app-installer.sh --help
```

## 📖 Usage

### 🎯 Interactive Mode

After running the script, you will see the main menu:

```
========================================
    Docker Application Installer v1.0       
========================================

Please select an option:
1) Basic Installation (Docker + Docker Compose)
2) Application Installation (Select apps to install)
3) Application Uninstall (Uninstall installed apps)
4) View Current Status
5) Exit
```

### 🎮 Menu Operations

#### 1️⃣ Basic Installation
- Install only Docker and Docker Compose
- Suitable for users who need custom configuration

#### 2️⃣ Application Installation
- Select applications to install
- Support custom ports
- Automatically create directory structure

#### 3️⃣ Application Uninstall
- Uninstall installed applications
- Option to retain data directories
- Support batch uninstallation

#### 4️⃣ View Status
- Display Docker service status
- List all container statuses
- Display system resource information

### ⌨️ Command Line Mode

#### Basic Installation
```bash
# Install Docker components only
sudo ./docker-app-installer.sh --install-docker-only
```

#### Application Installation
```bash
# Install single application
sudo ./docker-app-installer.sh --install-apps --app portainer

# Install multiple applications
sudo ./docker-app-installer.sh --install-apps --app portainer --app qbittorrent

# Custom port installation
sudo ./docker-app-installer.sh --install-apps --app portainer --port portainer:9001
```

#### Application Uninstall
```bash
# Uninstall single application
sudo ./docker-app-installer.sh --uninstall-apps --app portainer

# Uninstall multiple applications
sudo ./docker-app-installer.sh --uninstall-apps --app portainer --app qbittorrent

# Uninstall all applications
sudo ./docker-app-installer.sh --uninstall-apps --all

# Interactive uninstall menu
sudo ./docker-app-installer.sh --uninstall
```

#### Other Functions
```bash
# View system status
sudo ./docker-app-installer.sh --status

# Show help information
./docker-app-installer.sh --help
```

## 📁 Directory Structure

The script creates the following directory structure in `/home/docker`:

```
/home/docker/
├── portainer/
│   └── data/
├── qbittorrent/
│   ├── config/
│   ├── downloads/
│   └── watch/
├── vertex/
│   └── (application data)
├── nginx-proxy-manager/
│   ├── data/
│   └── letsencrypt/
└── transmission/
    ├── config/
    ├── downloads/
    └── watch/
```

## 🔧 Advanced Configuration

### Custom Data Directory

Edit the `DOCKER_BASE_DIR` variable in the script:

```bash
# Default directory
DOCKER_BASE_DIR="/home/docker"

# Custom directory
DOCKER_BASE_DIR="/data/docker"
```

### Custom Application Ports

Select "p) Configure Ports" in the application selection menu or use command line parameters:

```bash
sudo ./docker-app-installer.sh --install-apps --app portainer --port portainer:9001
```

### Application-Specific Configuration

#### Portainer
- **Default Port**: 9000
- **Data Directory**: `/home/docker/portainer/data`
- **First Access**: Need to create administrator account

#### qBittorrent
- **Default Port**: 8080
- **Version**: 4.5.5
- **Default User**: admin
- **Get Password**: `docker logs qbittorrent`

#### Vertex
- **Default Port**: 3000
- **Image**: lswl/vertex:stable
- **Data Directory**: `/home/docker/vertex`
- **Timezone**: Asia/Shanghai

#### Nginx Proxy Manager
- **Default Port**: 81 (management interface), 80/443 (proxy)
- **Default Login**: admin@example.com / changeme

#### Transmission
- **Default Port**: 9091
- **Default Login**: admin / changeme

## 🛡️ Security Features

### Permission Checks
- Automatic Root permission verification
- User group management (docker group)

### System Checks
- Operating system compatibility verification
- Docker service status checks

### Security Confirmations
- Require 'YES' confirmation before uninstallation
- Separate confirmation before data deletion
- Port conflict detection

### Error Handling
- Comprehensive error capture mechanisms
- Rollback mechanisms on failure
- Detailed log output

## 🔍 Troubleshooting

### Common Issues

#### 1. Insufficient Permissions
```bash
# Solution: Run with sudo
sudo ./docker-app-installer.sh
```

#### 2. Docker Service Start Failure
```bash
# Check Docker status
sudo systemctl status docker

# Restart Docker service
sudo systemctl restart docker
```

#### 3. Port Already in Use
```bash
# Check port usage
sudo netstat -tulpn | grep :port_number

# Or use ss command
sudo ss -tulpn | grep :port_number
```

#### 4. Container Start Failure
```bash
# View container logs
docker logs container_name

# View container status
docker ps -a
```

### Log Viewing

The script displays detailed log information during execution:

- `[INFO]`: General information
- `[SUCCESS]`: Successful operations
- `[WARNING]`: Warning information
- `[ERROR]`: Error information

### Manual Cleanup

If complete cleanup is needed:

```bash
# Stop all containers
docker stop $(docker ps -q)

# Remove all containers
docker rm $(docker ps -aq)

# Clean up images
docker image prune -f

# Remove data directory
sudo rm -rf /home/docker
```

## 🤝 Contributing

Welcome to submit Issues and Pull Requests!

### Reporting Issues

1. Check if the same issue already exists
2. Provide detailed environment information
3. Include error logs and reproduction steps

### Submitting Code

1. Fork the project
2. Create a feature branch
3. Commit changes
4. Create Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issue Reports**: [GitHub Issues](https://github.com/Topazios/docker-app-installer/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/Topazios/docker-app-installer/discussions)

## 📈 Changelog

### v1.0 (Current Version)
- ✨ Initial release
- 🐳 Support for Docker + Docker Compose automatic installation
- 📦 Support for 5 popular applications
- 🗑️ Complete uninstall functionality
- 🎛️ Interactive and command-line dual modes
- 🔒 Comprehensive security mechanisms

---

⭐ If this project helps you, please give it a Star! 