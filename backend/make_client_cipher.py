from kyber_py.ml_kem import ML_KEM_768, ML_KEM_1024

def client_encaps(level: str, server_public_key_hex: str):
    # Remove accidental spaces/newlines
    server_public_key_hex = server_public_key_hex.strip()

    ek = bytes.fromhex(server_public_key_hex)

    if level == "1024":
        shared, ct = ML_KEM_1024.encaps(ek)
    else:
        shared, ct = ML_KEM_768.encaps(ek)

    return shared, ct.hex()
