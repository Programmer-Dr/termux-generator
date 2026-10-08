#!/data/data/com.termux/files/usr/bin/bash
# Fix CRLF → LF on all shell scripts and config files
set -e

cd "$(dirname "$0")"

echo "[*] Converting line endings to LF..."

# Convert every shell script
find . -type f -name "*.sh" -not -path "./.git/*" -print0 | while IFS= read -r -d '' f; do
    if grep -q $'\r' "$f"; then
        echo "  fixing: $f"
        sed -i 's/\r$//' "$f"
    fi
done

# Convert other common text files that might have CRLF
for f in build-termux.sh scripts/termux_generator_utils.sh \
         scripts/termux_generator_steps.sh scripts/termux_generator_all.sh \
         .gitattributes; do
    if [ -f "$f" ] && grep -q $'\r' "$f" 2>/dev/null; then
        echo "  fixing: $f"
        sed -i 's/\r$//' "$f"
    fi
done

echo "[*] Done. Verifying with 'file':"
file build-termux.sh scripts/termux_generator_*.sh

echo
echo "[*] Expected output: 'ASCII text' or 'UTF-8 text'."
echo "[*] BAD output:       'with CRLF line terminators'."
