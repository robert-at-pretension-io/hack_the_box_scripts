#!/bin/bash

# ------------------------------------------------------------------------------
# Comprehensive Reconnaissance Tool
# A single script that performs various recon/enumeration tasks on a given target.
#
# Usage:
#   ./recon_script.sh <target>
# Example:
#   ./recon_script.sh example.com
#
# Author: [Your Name]
# ------------------------------------------------------------------------------

# -------------------------[ Terminal Colors ]-----------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

# -------------------------[ Usage & Input Checks ]------------------------------
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No target specified${NC}"
    echo "Usage: $0 <target>"
    exit 1
fi

TARGET=$1

# Create a timestamp-based output directory
OUTPUT_DIR="recon_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

LOGFILE="$OUTPUT_DIR/full_recon.log"

# -------------------------[ Helper Functions ]----------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

log() {
    # Logs to both stdout (with color) and LOGFILE (no color).
    # The color codes are stripped when redirected to the logfile by default.
    echo -e "$1" | tee -a "$LOGFILE"
}

run_command() {
    local cmd="$1"
    local description="$2"
    local output_file="$3"

    # Print heading and run command
    log "\n${PURPLE}=== Running $description ===${NC}"
    log "${CYAN}Command: $cmd${NC}"

    if eval "$cmd" > "$output_file" 2>&1; then
        log "${GREEN}✓ $description completed successfully${NC}"
        log "${CYAN}Results saved to: $output_file${NC}"
    else
        log "${RED}✗ $description encountered errors. Check the output in: $output_file${NC}"
    fi
}

# -------------------------[ Start of Script Output ]----------------------------
log "${BLUE}=================================${NC}"
log "${BLUE} Comprehensive Reconnaissance Tool${NC}"
log "${BLUE} Target: $TARGET${NC}"
log "${BLUE} Start Time: $(date)${NC}"
log "${BLUE}=================================${NC}"

# -------------------------[ Basic Reachability Check ]--------------------------
if ! ping -c 1 "$TARGET" >/dev/null 2>&1; then
    log "${YELLOW}Warning: Target does not respond to ping.${NC}"
    log "${YELLOW}Proceeding with caution...${NC}"
fi

# ------------------------------------------------------------------------------
# 1. WHOIS Lookup
# ------------------------------------------------------------------------------
if command_exists whois; then
    log "\n${CYAN}[+] Performing WHOIS lookup...${NC}"
    whois "$TARGET" > "$OUTPUT_DIR/whois.txt"
    # Log relevant lines:
    log "${GREEN}Relevant WHOIS lines:${NC}"
    log "$(grep -E 'Registrant|Organization|Email|Name|Phone' "$OUTPUT_DIR/whois.txt" 2>/dev/null)"
else
    log "${RED}[!] whois not found. Skipping WHOIS lookup.${NC}"
fi

# ------------------------------------------------------------------------------
# 2. Basic DNS Lookups
# ------------------------------------------------------------------------------
if command_exists host; then
    log "\n${CYAN}[+] Performing basic DNS lookups with 'host'...${NC}"
    host "$TARGET" > "$OUTPUT_DIR/dns_basic.txt" 2>&1
    log "${GREEN}host output saved in dns_basic.txt${NC}"
else
    log "${RED}[!] 'host' command not found. Skipping basic DNS lookup.${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Subdomain Enumeration (amass, dnsrecon, fierce, dnsenum)
# ------------------------------------------------------------------------------
if command_exists amass; then
    run_command \
        "amass enum -d $TARGET" \
        "Amass Subdomain Enumeration" \
        "$OUTPUT_DIR/amass.txt"
else
    log "${RED}[!] amass not found. Skipping Amass enumeration.${NC}"
fi

if command_exists dnsrecon; then
    run_command \
        "dnsrecon -d $TARGET -t std" \
        "DNSRecon" \
        "$OUTPUT_DIR/dnsrecon.txt"
else
    log "${RED}[!] dnsrecon not found. Skipping DNSRecon.${NC}"
fi

if command_exists fierce; then
    run_command \
        "fierce --domain $TARGET" \
        "Fierce DNS Enumeration" \
        "$OUTPUT_DIR/fierce.txt"
else
    log "${RED}[!] fierce not found. Skipping Fierce enumeration.${NC}"
fi

if command_exists dnsenum; then
    run_command \
        "dnsenum $TARGET" \
        "dnsenum Subdomain Enumeration" \
        "$OUTPUT_DIR/dnsenum.txt"
else
    log "${RED}[!] dnsenum not found. Skipping dnsenum enumeration.${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Port Scanning - masscan (requires sudo for raw socket in many cases)
# ------------------------------------------------------------------------------
OPEN_PORTS=""
if command_exists masscan; then
    log "\n${CYAN}[+] Running initial masscan scan (all TCP ports)...${NC}"

    if [ "$EUID" -ne 0 ]; then
        log "${YELLOW}[!] masscan typically needs sudo privileges for best results. Trying sudo...${NC}"
    fi

    sudo masscan "$TARGET" -p1-65535 --rate=1000 --wait=5 > "$OUTPUT_DIR/masscan.txt" 2>&1

    if grep -q "Discovered open port" "$OUTPUT_DIR/masscan.txt"; then
        # Extract the discovered open ports from masscan
        OPEN_PORTS=$(grep "Discovered" "$OUTPUT_DIR/masscan.txt" \
            | awk '{print $4}' | cut -d "/" -f 1 \
            | sort -n | tr '\n' ',' | sed 's/,$//')
        log "${GREEN}Masscan found open ports: $OPEN_PORTS${NC}"
    else
        log "${YELLOW}No open ports found by masscan, or none parsed. Will attempt full Nmap anyway.${NC}"
    fi
else
    log "${RED}[!] masscan not found. Skipping initial masscan scan.${NC}"
fi

# ------------------------------------------------------------------------------
# 5. Detailed Nmap Scan
# ------------------------------------------------------------------------------
if command_exists nmap; then
    log "\n${CYAN}[+] Running Nmap scan...${NC}"
    # If we have open ports from masscan, use them; else do a full -p- scan.
    if [ -n "$OPEN_PORTS" ]; then
        run_command \
            "nmap -sV -sC -p$OPEN_PORTS -oA $OUTPUT_DIR/nmap $TARGET" \
            "Nmap (version + default scripts, known ports)" \
            "/dev/null"
    else
        run_command \
            "nmap -sV -sC -p- -oA $OUTPUT_DIR/nmap $TARGET" \
            "Nmap (version + default scripts, all ports)" \
            "/dev/null"
    fi
else
    log "${RED}[!] nmap not found. Skipping Nmap scan.${NC}"
fi

# ------------------------------------------------------------------------------
# 6. Check for SMB/Windows Services => Enum4Linux
# ------------------------------------------------------------------------------
if [ -f "$OUTPUT_DIR/nmap.gnmap" ]; then
    if grep -qE "445/open|139/open" "$OUTPUT_DIR/nmap.gnmap"; then
        if command_exists enum4linux; then
            run_command \
                "enum4linux -a $TARGET" \
                "Enum4Linux (SMB Enumeration)" \
                "$OUTPUT_DIR/enum4linux.txt"
        else
            log "${RED}[!] enum4linux not found. Skipping SMB enumeration.${NC}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 7. Web Reconnaissance => TheHarvester (if HTTP/HTTPS open)
# ------------------------------------------------------------------------------
if [ -f "$OUTPUT_DIR/nmap.gnmap" ]; then
    if grep -qE "80/open|443/open" "$OUTPUT_DIR/nmap.gnmap"; then
        if command_exists theHarvester; then
            run_command \
                "theHarvester -d $TARGET -b all" \
                "theHarvester (Web OSINT)" \
                "$OUTPUT_DIR/theharvester.txt"
        else
            log "${RED}[!] theHarvester not found. Skipping Web OSINT enumeration.${NC}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 8. Metadata Extraction => exiftool
#    By default, exiftool is used on local files (images/docs).
#    If you want to test exiftool usage, you could do:
#       wget -r -l1 -P "$OUTPUT_DIR/downloaded" http://$TARGET
#       exiftool "$OUTPUT_DIR/downloaded"
# ------------------------------------------------------------------------------
if command_exists exiftool; then
    # Example stub for local analysis if you had discovered/collected files:
    # We'll only do something if we found an HTTP service and want to fetch top-level files.

    # Check if port 80 or 443 is open to attempt a quick web fetch
    if [ -f "$OUTPUT_DIR/nmap.gnmap" ] && grep -qE "80/open|443/open" "$OUTPUT_DIR/nmap.gnmap"; then
        log "\n${CYAN}[+] Attempting to download front page to extract metadata...${NC}"
        DOWNLOAD_DIR="$OUTPUT_DIR/downloaded_site"
        mkdir -p "$DOWNLOAD_DIR"

        # For demonstration: attempt a shallow crawl. Might fail if TLS issues or domain mismatch.
        # If your target is purely IP-based or doesn't have an HTTP index, this may do nothing.
        wget -r -l1 -nd -P "$DOWNLOAD_DIR" -e robots=off "http://$TARGET" 2>>"$LOGFILE"

        if [ "$(ls -A "$DOWNLOAD_DIR" 2>/dev/null)" ]; then
            run_command \
                "exiftool $DOWNLOAD_DIR" \
                "Exiftool (metadata extraction on downloaded files)" \
                "$OUTPUT_DIR/exiftool.txt"
        else
            log "${YELLOW}No files downloaded. Skipping Exiftool step.${NC}"
        fi
    else
        log "${YELLOW}HTTP/HTTPS not detected or no nmap.gnmap. Skipping exiftool download test.${NC}"
    fi
else
    log "${RED}[!] exiftool not found. Skipping metadata extraction.${NC}"
fi

# ------------------------------------------------------------------------------
# 9. Recon-ng => Automated script usage
# ------------------------------------------------------------------------------
if command_exists recon-ng; then
    log "\n${CYAN}[+] Setting up Recon-ng workspace and running sample modules...${NC}"
    # Build an rc script for recon-ng
    cat << EOF > "$OUTPUT_DIR/recon-ng-script.rc"
workspaces create $TARGET
workspaces select $TARGET
add domains $TARGET
use recon/domains-hosts/bing_domain_web
set SOURCE $TARGET
run
use recon/hosts-hosts/resolve
run
exit
EOF

    run_command \
        "recon-ng -r $OUTPUT_DIR/recon-ng-script.rc" \
        "Recon-ng (sample modules)" \
        "$OUTPUT_DIR/recon-ng.txt"
else
    log "${RED}[!] recon-ng not found. Skipping Recon-ng steps.${NC}"
fi

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
log "\n${GREEN}=== Reconnaissance Complete ===${NC}"
log "${BLUE}Target: $TARGET${NC}"
log "${BLUE}End Time: $(date)${NC}"
log "${BLUE}Output Directory: $OUTPUT_DIR${NC}"
log "${BLUE}Log File: $LOGFILE${NC}"

# ------------------------------------------------------------------------------
# Create a Basic HTML Report
# ------------------------------------------------------------------------------
REPORT_HTML="$OUTPUT_DIR/report.html"
log "${CYAN}Generating HTML report: $REPORT_HTML${NC}"

cat > "$REPORT_HTML" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Reconnaissance Report - $TARGET</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f7f9fc; }
        h1 { color: #2c3e50; }
        .section { margin: 20px 0; padding: 10px; background: #fff; border: 1px solid #ccc; }
        .title { font-size: 1.2em; color: #34495e; margin-bottom: 5px; }
        .timestamp { font-size: 0.9em; color: #888; margin-bottom: 10px; }
        pre { background: #fafafa; padding: 10px; border: 1px dashed #ccc; }
        .success { color: #27ae60; }
        .warning { color: #e67e22; }
        .error { color: #c0392b; }
        .subtitle { color: #2c3e50; margin-top: 0; }
    </style>
</head>
<body>
    <h1>Reconnaissance Report - $TARGET</h1>
    <div class="section">
        <p class="timestamp">Report generated on: $(date)</p>
        <p>Output Directory: $OUTPUT_DIR</p>
    </div>
EOF

# Loop through all .txt files created for each tool and include them
for file in "$OUTPUT_DIR"/*.txt; do
    if [ -f "$file" ]; then
        TOOL_NAME=$(basename "$file" .txt)
        echo "<div class='section'>" >> "$REPORT_HTML"
        echo "<div class='title'>Results: $TOOL_NAME</div>" >> "$REPORT_HTML"
        echo "<pre>" >> "$REPORT_HTML"
        cat "$file" >> "$REPORT_HTML"
        echo "</pre>" >> "$REPORT_HTML"
        echo "</div>" >> "$REPORT_HTML"
    fi
done

cat << EOF >> "$REPORT_HTML"
</body>
</html>
EOF

log "${GREEN}HTML report generated: $REPORT_HTML${NC}"
