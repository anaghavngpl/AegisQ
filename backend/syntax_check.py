import sys
try:
    import crypto_engine
    print("crypto_engine.py: Syntax OK")
except Exception as e:
    print(f"crypto_engine.py: Error: {e}")
    sys.exit(1)

try:
    import main
    print("main.py: Syntax OK")
except Exception as e:
    print(f"main.py: Error: {e}")
    sys.exit(1)
