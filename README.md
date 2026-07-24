# StuAuth

**Private. Offline. Yours.**

StuAuth is a local TOTP/HOTP authenticator designed for users who want full control over their secrets.

No cloud.
No forced synchronization.
No user account.
No telemetry.

Everything stays on your devices.

---

## Why StuAuth?

Most modern authenticator applications rely on cloud services, automatic synchronization, or third-party accounts.

StuAuth takes the opposite approach:

- Local-only storage
- Offline code generation
- Manual backups
- Optional LAN synchronization
- No dependency on external providers

**You own your data.**

---

## Features

### OTP Authentication

- TOTP (RFC 6238)
- HOTP support
- Offline code generation
- Automatic code refresh

### Account Management

- Folder-based organization
- Rename folders and accounts
- Manual Base32 secret entry
- Lightweight and simple interface

### Import

- Import from `otpauth://` URIs
- Import from text files
- QR Code scanning
- Direct screen QR capture
- Google Authenticator Migration QR import

### Export

- Text export
- PNG QR Code export
- Manual account backups

### Network Synchronization

- Built-in local HTTP server
- Synchronization between devices on the same network
- LAN host discovery
- No remote services

### Security

- AES‑256‑GCM encryption
- PBKDF2‑HMAC‑SHA256 key derivation
- Random salt generation
- Random IV generation
- Optional master password
- Secure memory wiping for sensitive secrets

### Desktop Integration

- System Tray support
- Quick lock / unlock
- Single-instance protection
- Time synchronization support

### Languages

- 🇫🇷 French
- 🇬🇧 English
- 🏴 Breton
- 🇯🇵 Japanese

---

## Security Model

Data is stored locally in an encrypted file.

When a master password is enabled:

- Data is protected using AES‑256‑GCM
- Encryption keys are derived using PBKDF2‑HMAC‑SHA256
- Passwords are never stored in plain text

When no master password is configured:

- A local device-specific key is generated automatically.

### Important

StuAuth is not a password manager.

It is designed specifically for storing and managing OTP secrets locally.

---

## Local Synchronization

StuAuth can share accounts between trusted devices on the same local network.

Port used:

```text
19755/TCP
```

⚠️ **Important**

Never expose this port directly to the Internet.

The synchronization feature is intended for trusted local networks only.

---

## Desktop Version

Built with:

- C++
- Qt 6
- OpenSSL
- ZXing

### Build

```bash
git clone https://github.com/Spiritecho777/StuAuth.git
cd StuAuth

cmake -B build
cmake --build build --config Release
```

---

## Android Version

An Android version built with .NET MAUI is also available.

👉 **Download:**

[StuAuth Android](https://github.com/Spiritecho777/StuAuthMobile/releases)

### Features

- Offline OTP generation
- Local synchronization with StuAuth Desktop
- Google Authenticator import
- Local account storage

---

## Firefox Extension

A Firefox extension is also available.

👉 **Download:**

[StuAuth Firefox Extension](https://github.com/Spiritecho777/StuAuthWeb/releases)

### Features

- Quick access to OTP codes
- Fully local operation
- Compatible with StuAuth exports
- No cloud dependency

---

## Philosophy

StuAuth is intentionally simple.

Project goals:

✅ Offline First  
✅ No Cloud  
✅ No Telemetry  
✅ User Controlled Backups  
✅ Lightweight  
✅ Open Source

Built primarily for personal use and shared publicly as-is.

---

## License

MIT License

You are free to:

- Use
- Modify
- Redistribute
- Integrate into your own projects

No warranty provided.

---

## Roadmap Ideas

Possible future features:

- WebAuthn / Passkeys support
- Portable encrypted backups
- End-to-end encrypted synchronization
- Webcam QR scanner
- Instant account search
- Custom themes

---

## Author

**Spiritecho**

If you find this project useful:

⭐ Star the repository  
🍴 Fork it  
🐛 Report bugs  
💡 Suggest improvements

---

# StuAuth

**Your OTPs. Your Device. Your Control.**
