# Windows Kid Account Manager

![Windows 11](https://img.shields.io/badge/Windows-11%20Pro-0078D4?style=for-the-badge&logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Version](https://img.shields.io/badge/Version-2.5.1-brightgreen?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Active-success?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

A powerful GUI-based Windows 11 child account management tool that helps parents and administrators audit, lock down, and manage local user accounts without manually editing the registry, Local Group Policy, or browser settings.

---

## Screenshot

> Replace the image below with your actual screenshot.

![Windows Kid Account Manager]([images/screenshot.png](https://i.imgur.com/sX8v1IT.png))

---

## Key Features

### Windows Account Restrictions
- Hide sensitive Settings pages
- Block Control Panel and Settings access
- Disable Command Prompt
- Disable Registry Editor
- Disable Task Manager
- Remove Run command access
- Block removable USB storage
- Restrict Microsoft Store access

### Microsoft Edge Hardening
- Block extension installation
- Disable Developer Tools
- Disable InPrivate Browsing
- Prevent browser sign-in
- Disable synchronization
- Disable password saving
- Enforce SmartScreen
- Enable PUA protection

### AI Protection Controls
- Hide Copilot toolbar icon
- Disable Edge Sidebar
- Disable Copilot page context
- Disable AI writing assistance
- Built-in Kid Safe profile

### Website Management
- URL allow lists
- URL block lists
- Import/export TXT files
- Change auditing before deployment

### DNS Family Filtering
- CleanBrowsing Family
- OpenDNS FamilyShield
- Cloudflare Family
- Automatic (DHCP)

### Backup & Restore
- JSON backups
- Configuration comparison
- Restore previous settings
- Automatic backups before policy application

### Reporting
- Excel exports
- Policy audit reports
- Website lists
- DNS configuration reports

---

## Requirements

- Windows 11 Pro
- PowerShell 7+
- Administrator privileges

---

## Installation

```powershell
git clone https://github.com/YourUsername/Windows-Kid-Account-Manager.git
cd Windows-Kid-Account-Manager
.\KidAccountManager.ps1
```

---

## Folder Structure

```text
C:\Temp\KidLockdownManager\
├── Logs\
├── Backups\
├── Reports\
└── Config\
```

---

## Version

**Current Version:** 2.5.1

## License

MIT License
