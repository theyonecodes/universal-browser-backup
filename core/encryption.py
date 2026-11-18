"""
AES-256-GCM encryption for browser profile backups.
Uses cryptography library for authenticated encryption.
"""

import os
import base64
import json
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.fernet import Fernet
from typing import Optional, Tuple
import logging

log = logging.getLogger(__name__)

# Constants
KEY_DERIVATION_ITERATIONS = 100_000
SALT_SIZE = 16
NONCE_SIZE = 12
TAG_SIZE = 16


def derive_key(password: str, salt: bytes) -> bytes:
    """Derive a 32-byte AES-256 key from password using PBKDF2."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=KEY_DERIVATION_ITERATIONS,
    )
    return kdf.derive(password.encode('utf-8'))


def encrypt_file(input_path: str, output_path: str, password: str) -> dict:
    """
    Encrypt a file using AES-256-GCM.
    Returns metadata needed for decryption.
    """
    salt = os.urandom(SALT_SIZE)
    key = derive_key(password, salt)
    aesgcm = AESGCM(key)
    nonce = os.urandom(NONCE_SIZE)

    with open(input_path, 'rb') as f:
        plaintext = f.read()

    ciphertext = aesgcm.encrypt(nonce, plaintext, None)

    with open(output_path, 'wb') as f:
        f.write(salt + nonce + ciphertext)

    return {
        "encrypted": True,
        "algorithm": "AES-256-GCM",
        "salt": base64.b64encode(salt).decode('ascii'),
        "nonce": base64.b64encode(nonce).decode('ascii'),
        "size": len(ciphertext),
    }


def decrypt_file(input_path: str, output_path: str, password: str, metadata: dict) -> bool:
    """
    Decrypt a file using AES-256-GCM.
    metadata must contain: salt, nonce
    """
    try:
        salt = base64.b64decode(metadata['salt'])
        nonce = base64.b64decode(metadata['nonce'])
        key = derive_key(password, salt)
        aesgcm = AESGCM(key)

        with open(input_path, 'rb') as f:
            data = f.read()

        # Format: salt + nonce + ciphertext
        if len(data) < SALT_SIZE + NONCE_SIZE:
            raise ValueError("Invalid encrypted file format")

        ciphertext = data[SALT_SIZE + NONCE_SIZE:]
        plaintext = aesgcm.decrypt(nonce, ciphertext, None)

        with open(output_path, 'wb') as f:
            f.write(plaintext)

        return True
    except Exception as e:
        log.error(f"Decryption failed: {e}")
        return False


def encrypt_bytes(data: bytes, password: str) -> Tuple[bytes, dict]:
    """Encrypt bytes in memory."""
    salt = os.urandom(SALT_SIZE)
    key = derive_key(password, salt)
    aesgcm = AESGCM(key)
    nonce = os.urandom(NONCE_SIZE)
    ciphertext = aesgcm.encrypt(nonce, data, None)
    encrypted = salt + nonce + ciphertext
    metadata = {
        "encrypted": True,
        "algorithm": "AES-256-GCM",
        "salt": base64.b64encode(salt).decode('ascii'),
        "nonce": base64.b64encode(nonce).decode('ascii'),
    }
    return encrypted, metadata


def decrypt_bytes(encrypted: bytes, password: str, metadata: dict) -> bytes:
    """Decrypt bytes in memory."""
    salt = base64.b64decode(metadata['salt'])
    nonce = base64.b64decode(metadata['nonce'])
    key = derive_key(password, salt)
    aesgcm = AESGCM(key)
    ciphertext = encrypted[SALT_SIZE + NONCE_SIZE:]
    return aesgcm.decrypt(nonce, ciphertext, None)


def generate_recovery_key() -> str:
    """Generate a Fernet key for key escrow/recovery."""
    return Fernet.generate_key().decode('ascii')


def encrypt_with_recovery(data: bytes, password: str, recovery_key: str) -> dict:
    """
    Encrypt with password + create recovery wrapper using Fernet.
    Returns dict with encrypted data and recovery info.
    """
    # Encrypt with password (AES-GCM)
    encrypted_data, aes_meta = encrypt_bytes(data, password)
    
    # Encrypt the AES key with recovery key (Fernet)
    f = Fernet(recovery_key.encode('ascii'))
    aes_key = derive_key(password, base64.b64decode(aes_meta['salt']))
    recovery_wrapped = f.encrypt(aes_key)
    
    return {
        "data": base64.b64encode(encrypted_data).decode('ascii'),
        "aes_metadata": aes_meta,
        "recovery_wrapped": base64.b64encode(recovery_wrapped).decode('ascii'),
    }


def decrypt_with_recovery(encrypted_package: dict, password: str = None, recovery_key: str = None) -> bytes:
    """
    Decrypt using either password or recovery key.
    """
    aes_meta = encrypted_package['aes_metadata']
    encrypted_data = base64.b64decode(encrypted_package['data'])
    
    if password:
        return decrypt_bytes(encrypted_data, password, aes_meta)
    elif recovery_key:
        f = Fernet(recovery_key.encode('ascii'))
        recovery_wrapped = base64.b64decode(encrypted_package['recovery_wrapped'])
        aes_key = f.decrypt(recovery_wrapped)
        aesgcm = AESGCM(aes_key)
        salt = base64.b64decode(aes_meta['salt'])
        nonce = base64.b64decode(aes_meta['nonce'])
        ciphertext = encrypted_data[SALT_SIZE + NONCE_SIZE:]
        return aesgcm.decrypt(nonce, ciphertext, None)
    else:
        raise ValueError("Either password or recovery_key required")